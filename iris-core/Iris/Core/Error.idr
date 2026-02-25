module Iris.Core.Error

public export
data IrisError
  = SessionNotFound String
  | WindowNotFound String
  | PaneNotFound Nat
  | BackendError String
  | RecordingError String
  | ProtocolError String
