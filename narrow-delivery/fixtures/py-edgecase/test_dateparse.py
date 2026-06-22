from dateparse import parse_duration


def test_existing_cases():
    assert parse_duration("1h30m") == 5400
    assert parse_duration("45m") == 2700
    assert parse_duration("2h") == 7200
    assert parse_duration("90s") == 90
    assert parse_duration("1h30m15s") == 5415


def test_edge_cases():
    assert parse_duration("") == 0
    assert parse_duration("120") == 120  # bare number = seconds
