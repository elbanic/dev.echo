---
inclusion: always
---
<!------------------------------------------------------------------------------------
   Add rules to this file or a short description and have Kiro refine them for you.
   
   Learn about inclusion modes: https://kiro.dev/docs/steering/#inclusion-modes
-------------------------------------------------------------------------------------> 

## ⚠️ IMPORTANT: Context Management
**Before starting any task, ALWAYS read `KIRO.md` in the project root.**
This file contains:
- Current implementation progress
- Project structure overview
- Key file references
- Build commands

## Language guide
- interface: Swift, CLI
- Backend: Python, Strands Agents, boto3

## Natural Language Rules
### For Claude Code (AI Assistant)

| Context | Language |
|---------|----------|
| **All file generation** (code, comments, documentation, commit messages) | **English** |
| **Conversation with user** (explanations, Q&A, planning discussions) | **Korean** |

## Project References
- **Phase 1 Spec**: `.kiro/specs/dev-echo-phase1/` ✅ Complete
- **Phase 2 Spec**: `.kiro/specs/dev-echo-phase2/` (Cloud Services, Knowledge Base)
- **Status**: `KIRO.md` (implementation progress)
- **Swift Code**: `Sources/DevEcho/`
- **Python Code**: `backend/`

## Strands Agent References
- Quick Start: https://strandsagents.com/latest/documentation/docs/user-guide/quickstart/python/
- Knowledge Base Agent: https://strandsagents.com/latest/documentation/docs/examples/python/knowledge_base_agent/

## Build & Run Commands
```bash
# Swift
swift build                    # Build
swift run dev.echo             # Run CLI

# Python backend
cd backend
source .venv/bin/activate
python main.py                 # Run backend server

# Tests
pytest                         # Python tests (in backend/)
swift test                     # Swift tests
```

## Documentation rule
- Add details on how it was implemented to KIRO.md.
- If the existing method is changed, KIRO.md should also be updated.
- Do not update implementation progress in KIRO.md
