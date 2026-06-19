use crate::entry::{Entry, EntryStatus, NewEntry, tokens};
use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::cmp::Ordering;
use std::collections::{BTreeSet, HashMap, VecDeque};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;

#[derive(Debug, Clone, Default)]
pub struct ReferenceStore {
    entries: Vec<Entry>,
    next_id: usize,
}

impl ReferenceStore {
    pub fn new() -> Self {
        Self {
            entries: Vec::new(),
            next_id: 1,
        }
    }

    pub fn from_entries(entries: Vec<Entry>) -> Self {
        let next_id = entries
            .iter()
            .filter_map(|entry| entry.id.strip_prefix('e')?.parse::<usize>().ok())
            .max()
            .unwrap_or(0)
            + 1;

        Self { entries, next_id }
    }

    pub fn from_jsonl_path(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        if !path.exists() {
            return Ok(Self::new());
        }

        let file = fs::File::open(path)
            .with_context(|| format!("failed to open JSONL store {}", path.display()))?;
        let reader = BufReader::new(file);
        let mut entries = Vec::new();

        for (index, line) in reader.lines().enumerate() {
            let line = line.with_context(|| {
                format!("failed to read line {} from {}", index + 1, path.display())
            })?;
            if line.trim().is_empty() {
                continue;
            }

            let entry: Entry = serde_json::from_str(&line).with_context(|| {
                format!(
                    "failed to decode entry JSON at {}:{}",
                    path.display(),
                    index + 1
                )
            })?;
            entries.push(entry);
        }

        Ok(Self::from_entries(entries))
    }

    pub fn all(&self) -> &[Entry] {
        &self.entries
    }

    pub fn into_entries(self) -> Vec<Entry> {
        self.entries
    }

    pub fn get(&self, id: &str) -> Option<&Entry> {
        self.entries.iter().find(|entry| entry.id == id)
    }

    pub fn absorb(&mut self, entries: Vec<NewEntry>, fallback_author: &str) -> Vec<Entry> {
        entries
            .into_iter()
            .map(|entry| self.push(entry, fallback_author))
            .collect()
    }

    pub fn push(&mut self, entry: NewEntry, fallback_author: &str) -> Entry {
        let id = format!("e{}", self.next_id);
        self.next_id += 1;

        let entry = Entry::from_new(id, fallback_author, entry);
        self.entries.push(entry.clone());
        entry
    }

    pub fn serve(&self, query: &str, k: usize) -> Vec<Entry> {
        let query_tokens = tokens(query);
        let query_set = query_tokens.iter().collect::<BTreeSet<_>>();

        let mut scored = self
            .entries
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .filter_map(|entry| {
                let entry_tokens = tokens(&entry.text);
                let entry_set = entry_tokens.iter().collect::<BTreeSet<_>>();
                let overlap = query_set.intersection(&entry_set).count() as f32;
                let score = if query_set.is_empty() || entry_set.is_empty() {
                    0.0
                } else {
                    overlap / (query_set.len().max(entry_set.len()) as f32)
                };

                if score > 0.0 {
                    Some((score, entry))
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();

        scored.sort_by(|(left_score, left), (right_score, right)| {
            right_score
                .partial_cmp(left_score)
                .unwrap_or(Ordering::Equal)
                .then_with(|| entry_number(&left.id).cmp(&entry_number(&right.id)))
        });

        scored
            .into_iter()
            .take(k)
            .map(|(_, entry)| entry.clone())
            .collect()
    }

    pub fn retract(&mut self, id: &str, author: &str) -> Result<Vec<Entry>> {
        if self.get(id).is_none() {
            bail!("cannot retract unknown entry {id}");
        }
        Ok(self.mark_closure(
            id,
            None,
            EntryStatus::Retracted,
            "retracted_by",
            Value::String(author.to_string()),
        ))
    }

    /// Supersede `id` (and its downstream citation closure) with replacement
    /// `new_id`: the closure is marked `Superseded` with `superseded_by = new_id`,
    /// while `new_id` stays `Active`. Symmetric to `retract` (citation-closure
    /// withdrawal) but records *what replaced* the entry instead of *who pulled
    /// it*, so a changed question/claim is a first-class, provenance-linked event
    /// rather than a silent new run. The read path (input selectors, aggregate,
    /// serve) already filters `Active`, so superseded entries leave the live flow
    /// with no further wiring.
    pub fn supersede(&mut self, id: &str, new_id: &str) -> Result<Vec<Entry>> {
        if id == new_id {
            bail!("cannot supersede {id} with itself");
        }
        if self.get(id).is_none() {
            bail!("cannot supersede unknown entry {id}");
        }
        if self.get(new_id).is_none() {
            bail!("cannot supersede {id} with unknown replacement {new_id}");
        }
        Ok(self.mark_closure(
            id,
            Some(new_id),
            EntryStatus::Superseded,
            "superseded_by",
            Value::String(new_id.to_string()),
        ))
    }

    /// Mark `id` and its downstream citation closure with `status`, stamping
    /// `(meta_key, meta_value)` on each. `keep` (if set) is held `Active` even
    /// when it sits inside the closure — used by `supersede` so a replacement
    /// that cites the old entry is not buried with it. Returns the affected
    /// closure entries (the kept replacement excluded), mirroring the closure
    /// the human must see (no silent drop).
    fn mark_closure(
        &mut self,
        id: &str,
        keep: Option<&str>,
        status: EntryStatus,
        meta_key: &str,
        meta_value: Value,
    ) -> Vec<Entry> {
        let affected_set: BTreeSet<String> = self
            .downstream_closure(id)
            .into_iter()
            .filter(|affected| keep != Some(affected.as_str()))
            .collect();

        for entry in &mut self.entries {
            if keep == Some(entry.id.as_str()) {
                continue;
            }
            if entry.id == id || affected_set.contains(&entry.id) {
                entry.status = status.clone();
                entry.meta.insert(meta_key.to_string(), meta_value.clone());
            }
        }

        self.entries
            .iter()
            .filter(|entry| affected_set.contains(&entry.id))
            .cloned()
            .collect()
    }

    pub fn downstream_closure(&self, id: &str) -> Vec<String> {
        let mut reverse: HashMap<&str, Vec<&str>> = HashMap::new();
        for entry in self
            .entries
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
        {
            for citation in &entry.citations {
                reverse
                    .entry(citation.as_str())
                    .or_default()
                    .push(entry.id.as_str());
            }
        }

        let mut seen = BTreeSet::new();
        let mut queue = VecDeque::from([id.to_string()]);

        while let Some(current) = queue.pop_front() {
            if let Some(children) = reverse.get(current.as_str()) {
                for child in children {
                    if seen.insert((*child).to_string()) {
                        queue.push_back((*child).to_string());
                    }
                }
            }
        }

        seen.into_iter().collect()
    }

    pub fn append_jsonl(path: impl AsRef<Path>, entries: &[Entry]) -> Result<()> {
        let path = path.as_ref();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }

        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .with_context(|| format!("failed to open JSONL store {}", path.display()))?;

        for entry in entries {
            serde_json::to_writer(&mut file, entry)
                .with_context(|| format!("failed to encode entry {}", entry.id))?;
            file.write_all(b"\n")
                .with_context(|| format!("failed to write {}", path.display()))?;
        }

        Ok(())
    }

    pub fn write_jsonl(&self, path: impl AsRef<Path>) -> Result<()> {
        let path = path.as_ref();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }

        let mut file = fs::File::create(path)
            .with_context(|| format!("failed to create JSONL store {}", path.display()))?;

        for entry in &self.entries {
            serde_json::to_writer(&mut file, entry)
                .with_context(|| format!("failed to encode entry {}", entry.id))?;
            file.write_all(b"\n")
                .with_context(|| format!("failed to write {}", path.display()))?;
        }

        Ok(())
    }
}

fn entry_number(id: &str) -> usize {
    id.strip_prefix('e')
        .and_then(|number| number.parse::<usize>().ok())
        .unwrap_or(usize::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::EntryType;

    #[test]
    fn retract_marks_downstream_citation_closure() {
        let mut store = ReferenceStore::new();
        let e1 = store.push(NewEntry::new(EntryType::Claim, "a", "base"), "a");
        let e2 = store.push(
            NewEntry::new(EntryType::Claim, "b", "child").with_citations(vec![e1.id.clone()]),
            "b",
        );
        let e3 = store.push(
            NewEntry::new(EntryType::Claim, "c", "grandchild").with_citations(vec![e2.id.clone()]),
            "c",
        );
        let e4 = store.push(NewEntry::new(EntryType::Claim, "d", "unrelated"), "d");

        let affected = store.retract(&e1.id, "operator").unwrap();
        assert_eq!(
            affected
                .iter()
                .map(|entry| entry.id.as_str())
                .collect::<Vec<_>>(),
            vec![e2.id.as_str(), e3.id.as_str()]
        );
        assert_eq!(store.get(&e1.id).unwrap().status, EntryStatus::Retracted);
        assert_eq!(store.get(&e2.id).unwrap().status, EntryStatus::Retracted);
        assert_eq!(store.get(&e3.id).unwrap().status, EntryStatus::Retracted);
        assert_eq!(store.get(&e4.id).unwrap().status, EntryStatus::Active);
    }

    #[test]
    fn supersede_marks_closure_and_keeps_replacement_active() {
        let mut store = ReferenceStore::new();
        let q1 = store.push(NewEntry::new(EntryType::Question, "a", "old question"), "a");
        let d1 = store.push(
            NewEntry::new(EntryType::Decision, "b", "answer to old")
                .with_citations(vec![q1.id.clone()]),
            "b",
        );
        // Replacement question cites the old one (the reframe chain) — it sits
        // inside the closure but must stay Active.
        let q2 = store.push(
            NewEntry::new(EntryType::Question, "c", "reframed question")
                .with_citations(vec![q1.id.clone()]),
            "c",
        );

        let affected = store.supersede(&q1.id, &q2.id).unwrap();
        // Closure report excludes the kept replacement; only the stale answer.
        assert_eq!(
            affected
                .iter()
                .map(|entry| entry.id.as_str())
                .collect::<Vec<_>>(),
            vec![d1.id.as_str()]
        );
        assert_eq!(store.get(&q1.id).unwrap().status, EntryStatus::Superseded);
        assert_eq!(store.get(&d1.id).unwrap().status, EntryStatus::Superseded);
        assert_eq!(
            store.get(&d1.id).unwrap().meta.get("superseded_by").unwrap(),
            &Value::String(q2.id.clone())
        );
        // Replacement stays live despite citing the superseded question.
        assert_eq!(store.get(&q2.id).unwrap().status, EntryStatus::Active);
    }

    #[test]
    fn supersede_rejects_unknown_or_self_replacement() {
        let mut store = ReferenceStore::new();
        let q1 = store.push(NewEntry::new(EntryType::Question, "a", "q"), "a");
        assert!(store.supersede(&q1.id, "e999").is_err());
        assert!(store.supersede(&q1.id, &q1.id).is_err());
    }

    #[test]
    fn jsonl_round_trips_and_continues_ids() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("store.jsonl");
        let mut store = ReferenceStore::new();
        store.push(
            NewEntry::new(EntryType::Chunk, "scenario", "task text"),
            "scenario",
        );
        store.write_jsonl(&path).unwrap();

        let mut restored = ReferenceStore::from_jsonl_path(&path).unwrap();
        let next = restored.push(NewEntry::new(EntryType::Claim, "agent", "next"), "agent");
        assert_eq!(next.id, "e2");
    }
}
