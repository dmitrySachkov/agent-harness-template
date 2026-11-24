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

Keep this file short. When a lesson has become a check or a hook, delete its entry here.

---

