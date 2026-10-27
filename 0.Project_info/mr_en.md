# Professional Merge Request Generator

Generate a comprehensive and professional Merge Request following GitLab best practices based on the provided changes.

## Mandatory Structure
```markdown
## 🎯 Merge Request Overview
[Clear, concise description of what this MR accomplishes and why it's needed]

## 📋 Changes Summary
**Type:** [Feature/Bugfix/Hotfix/Refactor/Documentation/Performance/Security]
**Scope:** [Component/Module/Service affected]
**Breaking:** [Yes/No]

### 🔄 What's Changed
- **Added:** [New functionality, files, or features]
- **Modified:** [Changed behavior, updated files]
- **Fixed:** [Bugs resolved, issues addressed]
- **Removed:** [Deprecated code, unused files]

## 🏗️ Implementation Details
### Architecture Changes
[Describe any architectural decisions or patterns used]

### Key Components Modified
- `[component/file]` - [Brief description of changes]
- `[component/file]` - [Brief description of changes]

### Dependencies
- [ ] New dependencies added
- [ ] Dependencies updated
- [ ] Dependencies removed

## 🧪 Quality Assurance
### Testing Strategy
- [ ] **Unit Tests:** [Status/Coverage]
- [ ] **Integration Tests:** [Status/Coverage]
- [ ] **E2E Tests:** [Status/Coverage]
- [ ] **Manual Testing:** [Completed/In Progress]

### Test Coverage
- Previous coverage: [X]%
- Current coverage: [Y]%
- Diff: [+/-Z]%

### Testing Instructions
```bash
# Commands to test this MR
[Provide specific commands and steps]
```

## 📊 Performance Impact
- [ ] No performance impact
- [ ] Performance improved
- [ ] Performance degraded (explain in comments)
- [ ] Performance analysis required

**Metrics:** [Include any relevant performance data]

## 🔒 Security Considerations
- [ ] No security implications
- [ ] Security review required
- [ ] Vulnerability addressed
- [ ] New security measures implemented

## 🚀 Deployment Notes
### Pre-deployment Requirements
- [Any setup steps needed before deployment]

### Post-deployment Actions
- [Any actions needed after deployment]

### Rollback Plan
- [How to rollback if issues arise]

## 📸 Visual Changes
[Include screenshots, GIFs, or videos for UI/UX changes]

**Before:**
[Screenshot/description]

**After:**
[Screenshot/description]

## 🔗 Related Work
- **Issues:** Closes #[number], Relates to #[number]
- **Epic:** [Link to epic if applicable]
- **Documentation:** [Links to related docs]
- **Dependencies:** [Other MRs this depends on]

## ✅ Definition of Done
- [ ] Code meets acceptance criteria
- [ ] Code reviewed and approved
- [ ] Tests written and passing
- [ ] Documentation updated
- [ ] Performance acceptable
- [ ] Security considerations addressed
- [ ] Browser compatibility verified (if applicable)
- [ ] Mobile responsiveness checked (if applicable)

## 👥 Review Assignment
### Required Reviewers
- **@[tech-lead]** - Technical architecture review
- **@[domain-expert]** - Domain knowledge validation
- **@[security-team]** - Security review (if applicable)

### Optional Reviewers
- **@[team-member]** - Code style and best practices

## 📝 Additional Context
[Any additional information that reviewers should know about this change]

### Known Issues/Limitations
[List any known issues or limitations]

### Future Improvements
[List any follow-up work or improvements planned]
```

## Instructions for AI
1. **Thoroughly analyze** the provided changes to understand scope and complexity
2. **Categorize appropriately** using GitLab's MR conventions
3. **Fill relevant sections** - remove sections that don't apply
4. **Be specific and actionable** in all descriptions
5. **Include technical details** appropriate for the team level
6. **Consider deployment implications** and include relevant notes
7. **Use GitLab-specific features** like assignees, labels, and milestones references
8. **Write for multiple audiences** (developers, QA, DevOps, product)

## Changes to Analyze
```
[[CHANGES]]
```

**Generate ONLY the Merge Request content, without additional explanations.**
