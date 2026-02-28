---- MODULE CompressProtocol ----
EXTENDS Naturals, FiniteSets, Sequences

\* ===========================================================================
\* Constants
\* ===========================================================================

CONSTANTS
    Files,          \* Set of file identifiers
    Workers         \* Set of worker identifiers

\* ===========================================================================
\* Variables
\* ===========================================================================

VARIABLES
    fileState,      \* fileState[f] \in {"raw", "compressing", "verifying",
                    \*                   "compressed", "failed", "cleaned"}
    workerState,    \* workerState[w] \in {"idle", "compressing", "verifying"}
    workerFile,     \* workerFile[w] = file the worker is working on, or NULL
    originalExists, \* originalExists[f] \in BOOLEAN — original file on disk
    compressedExists \* compressedExists[f] \in BOOLEAN — .lz file on disk

vars == <<fileState, workerState, workerFile, originalExists, compressedExists>>

CONSTANTS NULL

\* ===========================================================================
\* Type Invariant
\* ===========================================================================

FileStates == {"raw", "compressing", "verifying", "compressed", "failed", "cleaned"}
WorkerStates == {"idle", "compressing", "verifying"}

TypeInvariant ==
    /\ fileState \in [Files -> FileStates]
    /\ workerState \in [Workers -> WorkerStates]
    /\ workerFile \in [Workers -> Files \cup {NULL}]
    /\ originalExists \in [Files -> BOOLEAN]
    /\ compressedExists \in [Files -> BOOLEAN]

\* ===========================================================================
\* Initial State
\* ===========================================================================

Init ==
    /\ fileState = [f \in Files |-> "raw"]
    /\ workerState = [w \in Workers |-> "idle"]
    /\ workerFile = [w \in Workers |-> NULL]
    /\ originalExists = [f \in Files |-> TRUE]
    /\ compressedExists = [f \in Files |-> FALSE]

\* ===========================================================================
\* Actions (placeholder — Next is stuttering only for now)
\* ===========================================================================

Next == UNCHANGED vars

Spec == Init /\ [][Next]_vars

====
