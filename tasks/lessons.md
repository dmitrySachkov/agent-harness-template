# Lessons

Every failure leaves infrastructure behind. Agents read this file before starting a task; `/retro` appends to it.

Entry format (newest at the bottom):

```
## <YYYY-MM-DD> <short title>
- failure: what happened, with evidence
- cause: what in the system allowed it (contract / context / tool / verification / policy / recovery / trace)
- fix: the ONE change made or proposed, and where it lives (ladder: policy > automated check > template > checklist > docs)
- status: applied | proposed (needs human) | one-off, no change
```

Write `fix` as a general rule, not as the story of this run. The story belongs in `failure`. Test: would the rule make sense to someone who was not there, on a different task? "Check the banner z-index on the checkout screen" will never fire again; "after a layout change, check that no interactive element is covered" will.

Keep this file short. When a lesson has become a check or a hook, delete its entry here.

---

