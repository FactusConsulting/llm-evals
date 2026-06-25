import re

_UNIT = {"h": 3600, "m": 60, "s": 1}


def parse_duration(s):
    """Parse strings like '1h30m', '45m', '2h', '90s' into total seconds.

    BUGS: a bare unitless number (e.g. '120') and the empty string '' are
    mishandled (the regex loop yields 0 / or misbehaves).
    """
    total = 0
    for value, unit in re.findall(r"(\d+)([hms])", s):
        total += int(value) * _UNIT[unit]
    return total
