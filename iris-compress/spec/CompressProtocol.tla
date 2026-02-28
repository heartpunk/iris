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
\* Failure and Cleanup Actions
\* ===========================================================================

\* Compression or verification fails — worker releases the file.
CompressFail(w) ==
    /\ workerState[w] \in {"compressing", "verifying"}
    /\ workerFile[w] /= NULL
    /\ LET f == workerFile[w] IN
        /\ fileState' = [fileState EXCEPT ![f] = "failed"]
        /\ workerState' = [workerState EXCEPT ![w] = "idle"]
        /\ workerFile' = [workerFile EXCEPT ![w] = NULL]
        /\ UNCHANGED <<originalExists, compressedExists>>

\* Delete the original file after successful compression and verification.
DeleteOriginal(f) ==
    /\ fileState[f] = "compressed"
    /\ originalExists[f] = TRUE
    /\ originalExists' = [originalExists EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<fileState, workerState, workerFile, compressedExists>>

\* Clean up after a failure: remove partial .lz if it exists, mark cleaned.
CleanupFailed(f) ==
    /\ fileState[f] = "failed"
    /\ compressedExists' = [compressedExists EXCEPT ![f] = FALSE]
    /\ fileState' = [fileState EXCEPT ![f] = "cleaned"]
    /\ UNCHANGED <<workerState, workerFile, originalExists>>

\* A cleaned file can be retried.
RetryFile(f) ==
    /\ fileState[f] = "cleaned"
    /\ originalExists[f] = TRUE
    /\ fileState' = [fileState EXCEPT ![f] = "raw"]
    /\ UNCHANGED <<workerState, workerFile, originalExists, compressedExists>>

\* ===========================================================================
\* Safety Invariants
\* ===========================================================================

\* No data loss: if original is gone, compressed must exist.
NoDataLoss ==
    \A f \in Files :
        ~originalExists[f] => compressedExists[f]

\* No corruption: a file marked "compressed" must have .lz on disk.
NoCorruption ==
    \A f \in Files :
        fileState[f] = "compressed" => compressedExists[f]

\* No duplicate work: at most one worker per file.
NoDuplicateWork ==
    \A w1, w2 \in Workers :
        (w1 /= w2 /\ workerFile[w1] /= NULL)
            => workerFile[w1] /= workerFile[w2]

\* ===========================================================================
\* Next-State Relation
\* ===========================================================================

Next ==
    \/ \E w \in Workers, f \in Files : PickUpFile(w, f)
    \/ \E w \in Workers : CompressComplete(w)
    \/ \E w \in Workers : VerifyOutput(w)
    \/ \E w \in Workers : CompressFail(w)
    \/ \E f \in Files : DeleteOriginal(f)
    \/ \E f \in Files : CleanupFailed(f)
    \/ \E f \in Files : RetryFile(f)

\* ===========================================================================
\* Specifications
\* ===========================================================================

Spec == Init /\ [][Next]_vars

\* Fair specification: every enabled action eventually occurs.
FairSpec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ===========================================================================
\* Liveness Property
\* ===========================================================================

\* Every file eventually reaches a terminal state (compressed with original
\* deleted, or failed with partial cleaned).
AllFilesProcessed ==
    <>(\A f \in Files :
        \/ (fileState[f] = "compressed" /\ ~originalExists[f])
        \/ fileState[f] = "cleaned")

====
