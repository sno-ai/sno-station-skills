#!/usr/bin/env bash
set -euo pipefail
skill="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$skill/SKILL.md" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text().split('### Step 5a-2', 1)[1]
formula = re.search(r'```python\n(.*?)\n```', text, re.S).group(1)
for inputs, expected in [
    (dict(mandated_wait=480, final=600, band_max_h=12, era_multiplier=0.4), 528),
    (dict(mandated_wait=480, final=600, band_max_h=1, era_multiplier=0.4), 504),
    (dict(mandated_wait=0, final=600, band_max_h=5, era_multiplier=0.4), 120),
]:
    values = dict(inputs)
    exec(formula, {}, values)
    assert abs(values['final'] - expected) < 1e-9, values
print('PASS fixed waiting time survives scaling and caps; ordinary work remains scaled')
PY
