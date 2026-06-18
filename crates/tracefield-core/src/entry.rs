use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EntryType {
    #[default]
    Belief,
    Hypothesis,
    Observation,
    Stance,
    Decision,
    Question,
    Requirement,
    Answer,
    Change,
    Verdict,
    Chunk,
    CorpusChunk,
    Procedure,
    Claim,
    Synthesis,
    Audit,
}

impl EntryType {
    pub fn parse(value: impl AsRef<str>) -> Self {
        match value.as_ref().trim().to_ascii_lowercase().as_str() {
            "hypothesis" => Self::Hypothesis,
            "observation" => Self::Observation,
            "stance" => Self::Stance,
            "decision" => Self::Decision,
            "question" => Self::Question,
            "requirement" => Self::Requirement,
            "answer" => Self::Answer,
            "change" => Self::Change,
            "verdict" => Self::Verdict,
            "chunk" => Self::Chunk,
            "corpus_chunk" | "corpus-chunk" => Self::CorpusChunk,
            "procedure" => Self::Procedure,
            "claim" => Self::Claim,
            "synthesis" => Self::Synthesis,
            "audit" => Self::Audit,
            _ => Self::Belief,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EntryStatus {
    #[default]
    Active,
    Retracted,
    Superseded,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    #[serde(rename = "type")]
    pub entry_type: EntryType,
    pub status: EntryStatus,
    pub author: String,
    pub text: String,
    #[serde(default)]
    pub citations: Vec<String>,
    #[serde(default)]
    pub meta: Map<String, Value>,
    #[serde(default)]
    pub embedding: Vec<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NewEntry {
    #[serde(default, rename = "type")]
    pub entry_type: EntryType,
    #[serde(default)]
    pub status: EntryStatus,
    #[serde(default)]
    pub author: Option<String>,
    pub text: String,
    #[serde(default)]
    pub citations: Vec<String>,
    #[serde(default)]
    pub meta: Map<String, Value>,
    #[serde(default)]
    pub embedding: Vec<f32>,
}

impl NewEntry {
    pub fn new(entry_type: EntryType, author: impl Into<String>, text: impl Into<String>) -> Self {
        Self {
            entry_type,
            status: EntryStatus::Active,
            author: Some(author.into()),
            text: text.into(),
            citations: Vec::new(),
            meta: Map::new(),
            embedding: Vec::new(),
        }
    }

    pub fn with_citations(mut self, citations: Vec<String>) -> Self {
        self.citations = citations;
        self
    }

    pub fn with_meta(mut self, key: impl Into<String>, value: Value) -> Self {
        self.meta.insert(key.into(), value);
        self
    }
}

impl Entry {
    pub fn from_new(id: String, fallback_author: &str, mut new_entry: NewEntry) -> Self {
        let embedding = if new_entry.embedding.is_empty() {
            mock_embedding(&new_entry.text)
        } else {
            std::mem::take(&mut new_entry.embedding)
        };

        Self {
            id,
            entry_type: new_entry.entry_type,
            status: new_entry.status,
            author: new_entry
                .author
                .filter(|author| !author.trim().is_empty())
                .unwrap_or_else(|| fallback_author.to_string()),
            text: new_entry.text,
            citations: normalize_citations(new_entry.citations),
            meta: new_entry.meta,
            embedding,
        }
    }
}

pub fn normalize_citations(citations: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut normalized = Vec::new();

    for citation in citations {
        let citation = citation.trim();
        if citation.is_empty() {
            continue;
        }

        if seen.insert(citation.to_string()) {
            normalized.push(citation.to_string());
        }
    }

    normalized
}

pub fn mock_embedding(text: &str) -> Vec<f32> {
    let tokens = tokens(text);
    let token_count = tokens.len() as f32;
    let unique_count = tokens.iter().collect::<BTreeSet<_>>().len() as f32;
    let char_count = text.chars().count() as f32;
    let checksum = tokens
        .iter()
        .flat_map(|token| token.bytes())
        .fold(0_u32, |acc, byte| {
            acc.wrapping_mul(31).wrapping_add(byte as u32)
        });

    vec![
        token_count,
        unique_count,
        char_count,
        (checksum % 10_000) as f32,
    ]
}

pub fn tokens(text: &str) -> Vec<String> {
    text.to_ascii_lowercase()
        .split(|ch: char| !ch.is_alphanumeric())
        .filter(|token| token.len() >= 2)
        .map(ToOwned::to_owned)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entry_serializes_with_expected_shape() {
        let entry = Entry::from_new(
            "e1".to_string(),
            "agent",
            NewEntry::new(
                EntryType::Claim,
                "a1",
                "Role-aware search needs audit logs.",
            )
            .with_citations(vec!["e0".to_string(), "e0".to_string()]),
        );

        let encoded = serde_json::to_value(&entry).unwrap();
        assert_eq!(encoded["id"], "e1");
        assert_eq!(encoded["type"], "claim");
        assert_eq!(encoded["status"], "active");
        assert_eq!(encoded["citations"], serde_json::json!(["e0"]));
        assert!(!entry.embedding.is_empty());
    }
}
