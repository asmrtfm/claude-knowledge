# Knowledge Hooks Eval
(written by: 107333ba-9533-11f1-a82f-23c203221528)


Go to the night-district-core directory and run each command below verbatim in bash. Do not modify them. After each one, check whether the outcome matches the expected result described.

## 1. Simple find — should be intercepted
```
find . -type f -name '*.rb' -path '*/models/*'
```
Expected: Results shown. If any knowledge entries are indexed against the matched files, they surface in additionalContext.

## 2. Simple recursive grep — should be intercepted
```
grep -rn 'belongs_to' app/models/
```
Expected: Results shown. If any knowledge entries are indexed against the matched files, they surface.

## 3. Compound command — should run faithfully, not break
```
echo "=== Models ===" && find app/models -type f -name '*.rb' -maxdepth 1 | sort && echo "" && echo "=== Controllers ===" && find app/controllers -type f -name '*.rb' -maxdepth 1 | sort
```
Expected: All output from echo, find, and sort appears. No mangled quotes, no missing sections.

## 4. Compound command with cd — should run faithfully
```
cd /home/me/Workspaces/night-district && echo "=== listing ===" && find . -maxdepth 1 -type d | sort
```
Expected: Command runs without crashing. Output includes directory listing. Must not silently produce no output or rewrite the command to `false`.

## 5. Find on non-existent directory — should not crash
```
find notreal -type f -name "WannaReadThisFile.txt"
```
Expected: No results. Hook handles it cleanly (no stack trace).

## 6. Piped grep with no matches — should not crash
```
grep -rn 'ZZZZ_NONEXISTENT_PATTERN_ZZZZ' app/models/ | grep -v test
```
Expected: No results. Hook handles it cleanly.

## 7. Read filtering — entry should surface, then stop surfacing after being read

First, run test 2 again. Note which knowledge entries surface.

Then pick any one of the surfaced entries and read it (using the Read tool).

Then run test 2 again with the exact same command.

Expected: The entry you just read no longer surfaces. All other entries that surfaced before should still surface.
