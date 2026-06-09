defmodule Tracefield.StanceTest do
  use ExUnit.Case, async: true

  alias Tracefield.{LLM, Stance}

  test "mock stance detects optimistic versus cautious consent" do
    optimistic = [
      "Customer logs can be treated as cleared for cross-system search because secondary use consent is comprehensive."
    ]

    cautious = [
      "Derived summaries and next-action recommendations may exceed the current consent scope for customer logs."
    ]

    result = Stance.assess("consent-secondary-use", optimistic, cautious, adapter: LLM.Mock)

    assert result.differs
    assert result.g1 =~ "Consent is broad"
    assert result.g2 =~ "exceed current"
  end

  test "mock stance does not differ for unrelated matching topic" do
    claims = [
      "Security teams need audit trails for retrieved sources and generated recommendations."
    ]

    result = Stance.assess("security-auditability", claims, claims, adapter: LLM.Mock)

    refute result.differs
  end
end
