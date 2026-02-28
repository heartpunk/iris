---- MODULE CompressProtocol ----
EXTENDS Naturals, FiniteSets, Sequences

\* ===========================================================================
\* Constants
\* ===========================================================================

CONSTANTS
    Files,          \* Set of file identifiers
    Workers,        \* Set of worker identifiers
    NULL,           \* Sentinel for "no file assigned"
    MaxRetries      \* Maximum compression attempts per file

\* ===========================================================================
\* Variables
\* ===========================================================================

VARIABLES
    fileState,       \* fileState[f] \in FileStates
    workerState,     \* workerState[w] \in WorkerStates
    workerFile,      \* workerFile[w] \in Files \cup {NULL}
    originalExists,  \* originalExists[f] \in BOOLEAN
    compressedExists,\* compressedExists[f] \in BOOLEAN
    retryCount       \* retryCount[f] \in 0..MaxRetries — attempts so far

vars == <<fileState, workerState, workerFile, originalExists, compressedExists, retryCount>>

\* ===========================================================================
\* Type Invariant
\* ===========================================================================

FileStates == {"raw", "compressing", "compressed", "failed", "permfailed"}
WorkerStates == {"idle", "compressing", "verifying"}

TypeInvariant ==
    /\ fileState \in [Files -> FileStates]
    /\ workerState \in [Workers -> WorkerStates]
    /\ workerFile \in [Workers -> Files \cup {NULL}]
    /\ originalExists \in [Files -> BOOLEAN]
    /\ compressedExists \in [Files -> BOOLEAN]
    /\ retryCount \in [Files -> 0..MaxRetries]

\* ===========================================================================
\* Initial State
\* ===========================================================================

Init ==
    /\ fileState = [f \in Files |-> "raw"]
    /\ workerState = [w \in Workers |-> "idle"]
    /\ workerFile = [w \in Workers |-> NULL]
    /\ originalExists = [f \in Files |-> TRUE]
    /\ compressedExists = [f \in Files |-> FALSE]
    /\ retryCount = [f \in Files |-> 0]

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
    /\ retryCount' = [retryCount EXCEPT ![f] = retryCount[f] + 1]
    /\ UNCHANGED <<originalExists, compressedExists>>

\* Compression completes successfully — .lz file now exists on disk.
CompressComplete(w) ==
    /\ workerState[w] = "compressing"
    /\ workerFile[w] /= NULL
    /\ LET f == workerFile[w] IN
        /\ workerState' = [workerState EXCEPT ![w] = "verifying"]
        /\ compressedExists' = [compressedExists EXCEPT ![f] = TRUE]
        /\ UNCHANGED <<fileState, workerFile, originalExists, retryCount>>

\* Verification succeeds — original can be removed.
VerifyOutput(w) ==
    /\ workerState[w] = "verifying"
    /\ workerFile[w] /= NULL
    /\ LET f == workerFile[w] IN
        /\ fileState' = [fileState EXCEPT ![f] = "compressed"]
        /\ workerState' = [workerState EXCEPT ![w] = "idle"]
        /\ workerFile' = [workerFile EXCEPT ![w] = NULL]
        /\ UNCHANGED <<originalExists, compressedExists, retryCount>>

\* ===========================================================================
\* Failure and Cleanup Actions
\* ===========================================================================

\* Compression or verification fails — worker releases the file.
\* If retries remain, file goes back to "failed" (eligible for cleanup+retry).
\* If retries exhausted, file is permanently failed.
CompressFail(w) ==
    /\ workerState[w] \in {"compressing", "verifying"}
    /\ workerFile[w] /= NULL
    /\ LET f == workerFile[w] IN
        /\ IF retryCount[f] >= MaxRetries
           THEN fileState' = [fileState EXCEPT ![f] = "permfailed"]
           ELSE fileState' = [fileState EXCEPT ![f] = "failed"]
        /\ workerState' = [workerState EXCEPT ![w] = "idle"]
        /\ workerFile' = [workerFile EXCEPT ![w] = NULL]
        /\ UNCHANGED <<originalExists, compressedExists, retryCount>>

\* Delete the original file after successful compression and verification.
DeleteOriginal(f) ==
    /\ fileState[f] = "compressed"
    /\ originalExists[f] = TRUE
    /\ originalExists' = [originalExists EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<fileState, workerState, workerFile, compressedExists, retryCount>>

\* Clean up partial .lz after a retryable failure, return to raw for retry.
CleanupAndRetry(f) ==
    /\ fileState[f] = "failed"
    /\ compressedExists' = [compressedExists EXCEPT ![f] = FALSE]
    /\ fileState' = [fileState EXCEPT ![f] = "raw"]
    /\ UNCHANGED <<workerState, workerFile, originalExists, retryCount>>

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

\* Original is preserved for any file that permanently failed.
PermFailedPreservesOriginal ==
    \A f \in Files :
        fileState[f] = "permfailed" => originalExists[f]

\* Retry count never exceeds the maximum.
RetryBound ==
    \A f \in Files : retryCount[f] <= MaxRetries

\* ===========================================================================
\* Termination
\* ===========================================================================

\* All files in terminal state, all workers idle — program is done.
Done ==
    /\ \A f \in Files : fileState[f] \in {"compressed", "permfailed"}
    /\ \A f \in Files :
        fileState[f] = "compressed" => ~originalExists[f]
    /\ \A w \in Workers : workerState[w] = "idle"
    /\ UNCHANGED vars

\* ===========================================================================
\* Next-State Relation
\* ===========================================================================

Next ==
    \/ \E w \in Workers, f \in Files : PickUpFile(w, f)
    \/ \E w \in Workers : CompressComplete(w)
    \/ \E w \in Workers : VerifyOutput(w)
    \/ \E w \in Workers : CompressFail(w)
    \/ \E f \in Files : DeleteOriginal(f)
    \/ \E f \in Files : CleanupAndRetry(f)
    \/ Done

\* ===========================================================================
\* Specifications
\* ===========================================================================

Spec == Init /\ [][Next]_vars

\* Fair specification: weak fairness on Next suffices because bounded retries
\* guarantee natural termination — no infinite cycles possible.
FairSpec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ===========================================================================
\* Liveness Property
\* ===========================================================================

\* Every file eventually reaches a terminal state: either successfully
\* compressed with original deleted, or permanently failed with original
\* preserved.
AllFilesProcessed ==
    <>(\A f \in Files :
        \/ (fileState[f] = "compressed" /\ ~originalExists[f])
        \/ (fileState[f] = "permfailed" /\ originalExists[f]))

====
