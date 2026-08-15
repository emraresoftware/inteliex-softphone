# Dervish IDE - Roadmap & TODOs

## Phase 1: Foundation (Current)

### ✅ Completed
- [x] Separate dervish-ide repo from emare_code/vscode
- [x] Patch-based approach (fleet-commands.patch)
- [x] Command namespace setup (emareideos.*)
- [x] Legacy alias mapping (dervish.* → emareideos.*)
- [x] Ticket socket bridge stubs
- [x] Documentation (ARCHITECTURE.md, DEVELOPMENT.md)
- [x] Scripts (setup-vscode.sh, build.sh)
- [x] emrecode backend running (lifecycle API + web UI)

### 🚧 In Progress / Blocked

#### 1. Traffic Browser Command Handler
**Issue**: Command registered but no implementation
```typescript
// fleetContribution.ts - NEEDS IMPLEMENTATION
registerCommand(EMAREIDEOS_COMMANDS.openTrafficBrowser, ...)
```
**What's needed**:
- [ ] WebView provider for network log panel
- [ ] Network interception API (via VS Code's web request API or debugger protocol)
- [ ] Log storage (in-memory or SQLite)
- [ ] UI: table of HTTP requests (method, URL, status, duration, size)
- [ ] Details panel: headers, body, response

**Estimated effort**: Medium (2-3 days)

#### 2. Traffic Live Refresh Handler
**Issue**: Similar to openTrafficBrowser but live streaming
```typescript
// Needs polling/WebSocket to capture network in real-time
registerCommand(EMAREIDEOS_COMMANDS.toggleTrafficLiveRefresh, ...)
```
**What's needed**:
- [ ] Debugger protocol hooks (Chrome DevTools Protocol if debugging browser)
- [ ] Or: Capture from emrecode WebSocket events
- [ ] Real-time UI updates (auto-refresh table)
- [ ] Toggle on/off state management

**Estimated effort**: Medium (depends on debugger integration)

#### 3. Report Issue Handler
**Issue**: Command framework exists, no context capture
```typescript
// Should capture workspace context + browser state
registerCommand(EMAREIDEOS_COMMANDS.reportIssue, ...)
```
**What's needed**:
- [ ] Collect stack trace (if error active)
- [ ] Collect file diffs (git diff if git repo)
- [ ] Collect test output (if test running)
- [ ] Collect console logs (from debugger)
- [ ] Collect network logs (from traffic browser)
- [ ] Call `/api/lifecycle/instances/{id}/events` → POST event
- [ ] Optional: open issue creation dialog
- [ ] Display confirmation with ticket URL

**Estimated effort**: Medium (2 days)

#### 4. Browser Fix Workflow Handler
**Issue**: Command defined, no handler logic
```typescript
// Should call emrecode AI bridge
registerCommand(EMAREIDEOS_COMMANDS.runBrowserFixWorkflow, ...)
```
**What's needed**:
- [ ] Collect error context (traffic logs + stack trace)
- [ ] POST to emrecode `/api/ai-routes` (call Claude/GPT for diagnosis)
- [ ] Parse AI suggestion (could be CORS fix, auth header, versioning, etc.)
- [ ] Display suggestion dialog
- [ ] Optional: auto-apply simple fixes

**Estimated effort**: Medium (1-2 days, depends on AI service)

#### 5. Browser Fix Full Chain Handler
**Issue**: Extended version of browser fix
```typescript
// runBrowserFixWorkflow + apply + test + commit
registerCommand(EMAREIDEOS_COMMANDS.runBrowserFixFullChain, ...)
```
**What's needed**:
- [ ] Build on runBrowserFixWorkflow
- [ ] Apply fix to file (auto-patch)
- [ ] Run related tests (`npm test` or pytest)
- [ ] Commit if tests pass
- [ ] Rollback if tests fail
- [ ] Report status

**Estimated effort**: High (3-4 days)

#### 6. Ticket Socket Bridge Implementation
**Partially done**: Configure/disconnect commands exist with logging
**What's needed**:
- [ ] Parse URL: `configureTicketSocketBridge("ws://jira:8080/socket")`
- [ ] WebSocket client setup
- [ ] Listen for ticket updates (push from backend/Jira)
- [ ] Sync issue state in IDE (show in sidebar)
- [ ] Handle disconnect/reconnect with backoff
- [ ] Error handling & recovery

**Estimated effort**: Medium (2 days)

---

## Phase 2: UI/UX Polish

### Traffic Browser Panel
- [ ] Sidebar integration (Explorer-like panel)
- [ ] Filter by method (GET, POST, etc.)
- [ ] Filter by status (2xx, 4xx, 5xx)
- [ ] Search by URL or status code
- [ ] Export HAR format
- [ ] Diff response formats (prev vs current)

**Estimated effort**: High (3-4 days)

### Issue Report Dialog
- [ ] Template system (bug template, feature template)
- [ ] Markdown preview
- [ ] Auto-fill reproducible steps
- [ ] Link to related issues (search backend)

**Estimated effort**: Medium (2 days)

### Ticket Sidebar
- [ ] Show assigned issues
- [ ] Quick status update
- [ ] Comment thread UI
- [ ] Link to commit (if issue mentioned in commit)

**Estimated effort**: Medium (2 days)

---

## Phase 3: Backend Integration

### emrecode Enhancements
- [ ] `POST /api/lifecycle/instances/{id}/events` — accept event payloads
  - event_type: "bug_report", "network_log", "test_failure"
  - captured_at, context, artifacts
- [ ] `POST /api/ai-routes` — diagnose endpoint (for fix workflow)
  - input: error context
  - output: suggestion + fix code
- [ ] `GET /api/tickets` — fetch from Jira/Linear (if bridge active)
- [ ] WebSocket `/ws` event types:
  - `instance.state_changed`
  - `ticket.updated`
  - `event.created` (for real-time issue sync)

**Estimated effort**: Medium (2-3 days)

### AI Bridge Service
- [ ] Connect to Claude/GPT API
- [ ] Prompt templates for:
  - CORS diagnosis
  - Auth error diagnosis
  - Network timeout troubleshooting
  - Test failure analysis
- [ ] Cache suggestions (avoid duplicate API calls)

**Estimated effort**: Medium (2 days)

### Ticket System Integration
- [ ] Jira API client
- [ ] Linear API client
- [ ] GitHub Issues API (optional)
- [ ] Webhook listener (for push updates)

**Estimated effort**: High (3-4 days)

---

## Phase 4: Advanced Features

### Traffic Analysis
- [ ] Performance timeline (waterfall chart)
- [ ] Critical path analysis
- [ ] Memory/CPU profiling integration
- [ ] Bundle size analysis (for API response payloads)

**Estimated effort**: High (5+ days)

### Automated Error Triage
- [ ] Group similar errors (stack trace fuzzy match)
- [ ] Show error trend (how many times in last 24h)
- [ ] Auto-assign severity (critical/high/medium/low)
- [ ] ML classification (known issue vs new issue)

**Estimated effort**: Very High (1-2 weeks)

### Test Integration
- [ ] Run tests directly from IDE panel
- [ ] Capture test logs in traffic browser
- [ ] Link test failure → API call that failed → ticket

**Estimated effort**: Medium (2-3 days)

### CI/CD Integration
- [ ] Show build status in IDE
- [ ] Log streaming (build console)
- [ ] Deploy from IDE (if permissions allow)

**Estimated effort**: Medium (2-3 days)

---

## New Feature Proposals

### 1. **Smart Context Menu**
When you right-click on a network request in traffic browser:
- "Analyze this error" → runBrowserFixWorkflow
- "Create issue from this" → reportIssue
- "Inspect in DevTools" → open Chrome DevTools
- "Replay request" → resend HTTP request

**Why**: Faster workflow, no need for commands

### 2. **Error Badge on Problems Panel**
Show real-time browser errors in VS Code Problems panel:
```
📍 browser:console:error
  at app.tsx:42
  "Cannot read property 'data' of undefined"
```
Click → navigate to code location

**Why**: Familiar VS Code UX, unified error view

### 3. **Live Debugger Connection**
Bi-directional link IDE ↔ Browser DevTools:
- Set breakpoint in IDE
- Automatically pauses browser
- Step through code in IDE
- Watch variables in IDE sidebar

**Why**: Copilot can help debug in real-time

### 4. **Performance Insights Sidebar**
Show metrics for current active file:
- Network requests from this file
- Average response time
- Error rate
- Bundle size impact

**Why**: Instant perf feedback while coding

### 5. **Collaborative Issue Tracking**
Multiple devs can:
- See same traffic logs (shared session)
- Comment on specific request
- Suggest fix (via Copilot)
- Merge fixes (git-like)

**Why**: Team debugging, knowledge sharing

### 6. **Automated Health Checks**
Run periodic checks:
- API health (ping /api/health)
- DB connectivity
- Auth token validity
- TLS cert expiry

Show status in status bar:
```
🟢 Services healthy | 3 API endpoints | DB: ✓ | Auth: ✓
```

**Why**: Early warning for infrastructure issues

### 7. **Request/Response Templates**
Save common request patterns:
- "Login flow" (POST /auth → captures token)
- "Pagination" (GET with limit/offset)
- "Error injection" (POST with invalid data)

Replay with one click

**Why**: Speed up manual testing

### 8. **Ticket-Driven Development**
Link ticket to code:
```
// TICKET: EMARE-1234 (Critical bug: CORS)
// https://jira.local/browse/EMARE-1234
function fixCORSHeaders() {
  response.headers['Access-Control-Allow-Origin'] = '*';
}
```

Show inline issue preview on hover

**Why**: Context awareness, auto-linking

### 9. **Network Request Replay History**
Record → edit → replay workflow:
1. Browser makes request
2. IDE captures it
3. Dev modifies headers/body
4. Dev replays (manual testing)
5. Results logged automatically

**Why**: Advanced debugging without test code

### 10. **Copilot + Traffic Browser**
Chat with Copilot about network logs:
- "Why is this request slow?"
- "What causes this 500 error?"
- "Is this a security issue?"

Copilot reads traffic logs + code context

**Why**: AI-powered debugging

---

## Maintenance & DevOps

### Documentation
- [ ] API documentation (OpenAPI/Swagger)
- [ ] Command reference (all emareideos.* commands)
- [ ] Troubleshooting guide
- [ ] Video tutorials

**Estimated effort**: Medium (2-3 days)

### Testing
- [ ] Unit tests for traffic browser
- [ ] Integration tests (IDE ↔ backend)
- [ ] E2E tests (full workflow)
- [ ] Performance benchmarks

**Estimated effort**: High (3-5 days)

### CI/CD
- [ ] GitHub Actions for build/test
- [ ] Automated releases (DMG, MSI, AppImage)
- [ ] Nightly builds

**Estimated effort**: Medium (2 days)

---

## Priority Matrix

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| Traffic Browser Handler | Medium | High | 🔴 P1 |
| Report Issue Handler | Medium | High | 🔴 P1 |
| Browser Fix Workflow | Medium | High | 🔴 P1 |
| Ticket Socket Bridge | Medium | Medium | 🟠 P2 |
| Traffic Live Refresh | Medium | Medium | 🟠 P2 |
| Fix Full Chain | High | Medium | 🟡 P3 |
| Smart Context Menu | Low | High | 🟡 P3 |
| Error Badge | Low | High | 🟡 P3 |
| Live Debugger | High | Medium | 🔵 P4 |
| Collab Issues | High | Low | 🔵 P4 |

---

## Known Blockers / Dependencies

1. **emrecode AI routes**: Need `/api/ai-routes` endpoint for fix workflow
2. **Ticket system credentials**: How to store Jira/Linear API keys safely?
3. **Browser DevTools Protocol**: Need access to browser instance (for network interception)
4. **Network logging**: May need browser extension or proxy for accurate capture

---

## Success Criteria (MVP)

- [x] IDE commands registered
- [ ] Traffic browser panel with 10+ requests
- [ ] Report issue → creates ticket in 30 seconds
- [ ] Fix workflow suggests fix in <5 seconds
- [ ] Ticket socket bridge syncs without errors
- [ ] <100ms latency for command execution
- [ ] No memory leaks (traffic logs cleaned after 1h)

---

## Next Steps

1. **Pick P1 feature** (suggest: Traffic Browser)
2. **Create feature branch** (`feat/traffic-browser`)
3. **Implement handler** + WebView
4. **Test locally**
5. **Update patch** (`patches/fleet-commands.patch`)
6. **Update CHANGELOG.md**
