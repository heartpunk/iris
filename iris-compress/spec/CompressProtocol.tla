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
\* Worker Actions
\* ===========================================================================

\* A worker picks up a raw file to compress.
PickUpFile(w, f) ==
    /\ workerState[w] = "idle"
    /\ fileState[f] = "raw"
    /\ workerState' = [workerState EXCEPT ![w] = "compressing"]
    /\ workerFile' = [workerFile EXCEPT ![w] = f]
    /\ fileState' = [fileState EXCEPT ![f] = "compressing"]
    /\ UNCHANGED <<originalExists, compressedExists>>

\* Compression completes successfully — .lz file now exists on disk.
CompressComplete(w) ==
    /\ workerState[w] = "compressing"
    /\ workerFile[w] /= NULL
    /\ LET f == workerFile[w] IN
        /\ workerState' = [workerState EXCEPT ![w] = "verifying"]
        /\ compressedExists' = [compressedExists EXCEPT ![f] = TRUE]
        /\ UNCHANGED <<fileState, workerFile, originalExists>>

\* Verification succeeds — original can be removed.
VerifyOutput(w) ==
    /\ workerState[w] = "verifying"
    /\ workerFile[w] /= NULL
    /\ LET f == workerFile[w] IN
        /\ fileState' = [fileState EXCEPT ![f] = "compressed"]
        /\ workerState' = [workerState EXCEPT ![w] = "idle"]
        /\ workerFile' = [workerFile EXCEPT ![w] = NULL]
        /\ UNCHANGED <<originalExists, compressedExists>>

\* ===========================================================================
\* Next-State Relation
\* ===========================================================================

Next ==
    \/ \E w \in Workers, f \in Files : PickUpFile(w, f)
    \/ \E w \in Workers : CompressComplete(w)
    \/ \E w \in Workers : VerifyOutput(w)

Spec == Init /\ [][Next]_vars

====
