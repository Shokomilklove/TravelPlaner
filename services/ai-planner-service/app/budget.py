"""Budget analysis and suggestions."""


def analyze_budget(total_estimated_cost, budget, currency="USD"):
    total = round(float(total_estimated_cost or 0.0), 2)

    if budget is None:
        return {
            "within_budget": None,
            "budget": None,
            "total_estimated_cost": total,
            "delta": None,
            "currency": currency,
            "suggestions": [
                "No budget was provided. Set a target budget to get tailored suggestions."
            ],
        }

    budget = round(float(budget), 2)
    delta = round(budget - total, 2)
    within = delta >= 0
    suggestions = []

    if within:
        suggestions.append(
            f"Estimated cost is within budget with {currency} {delta:.2f} to spare."
        )
        if budget > 0 and delta > budget * 0.2:
            suggestions.append(
                "You have significant headroom — consider upgrading accommodation "
                "or adding a guided activity or day trip."
            )
    else:
        over = abs(delta)
        suggestions.append(f"Estimated cost is over budget by {currency} {over:.2f}.")
        suggestions.append(
            "Consider more affordable accommodation, trimming paid activities, "
            "or shifting to off-peak travel dates to reduce flight costs."
        )

    return {
        "within_budget": within,
        "budget": budget,
        "total_estimated_cost": total,
        "delta": delta,
        "currency": currency,
        "suggestions": suggestions,
    }
