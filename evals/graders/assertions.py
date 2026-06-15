from dataclasses import dataclass, field


@dataclass
class EvalResult:
    passed: bool
    message: str
    details: dict = field(default_factory=dict)


def assert_eq(actual, expected, label: str = "") -> EvalResult:
    ok = actual == expected
    msg = f"{label + ': ' if label else ''}{actual!r} {'==' if ok else '!='} {expected!r}"
    return EvalResult(ok, msg)


def assert_true(condition: bool, label: str = "") -> EvalResult:
    msg = f"{label + ': ' if label else ''}{'true' if condition else 'false'}"
    return EvalResult(bool(condition), msg)


def assert_in(value, collection, label: str = "") -> EvalResult:
    ok = value in collection
    msg = f"{label + ': ' if label else ''}{value!r} {'in' if ok else 'not in'} collection"
    return EvalResult(ok, msg)


def assert_before(a, b, sequence: list, label: str = "") -> EvalResult:
    """Assert that `a` appears before `b` in `sequence`."""
    try:
        idx_a = sequence.index(a)
        idx_b = sequence.index(b)
        ok = idx_a < idx_b
        msg = f"{label + ': ' if label else ''}{a!r} at [{idx_a}], {b!r} at [{idx_b}] — {'correct order' if ok else 'wrong order'}"
    except ValueError as e:
        ok = False
        msg = f"{label + ': ' if label else ''}value not found in sequence: {e}"
    return EvalResult(ok, msg)


def run_assertions(results: list[EvalResult]) -> tuple[bool, str]:
    lines = [f"  [{'PASS' if r.passed else 'FAIL'}] {r.message}" for r in results]
    all_passed = all(r.passed for r in results)
    return all_passed, "\n".join(lines)
