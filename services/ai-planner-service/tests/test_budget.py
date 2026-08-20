from app.budget import analyze_budget


def test_within_budget():
    result = analyze_budget(750, 2000, "USD")
    assert result["within_budget"] is True
    assert result["delta"] == 1250
    assert result["suggestions"]


def test_over_budget():
    result = analyze_budget(2500, 2000, "USD")
    assert result["within_budget"] is False
    assert result["delta"] == -500
    assert any("over budget" in s.lower() for s in result["suggestions"])


def test_no_budget():
    result = analyze_budget(750, None, "EUR")
    assert result["within_budget"] is None
    assert result["budget"] is None
    assert result["currency"] == "EUR"
    assert result["total_estimated_cost"] == 750
