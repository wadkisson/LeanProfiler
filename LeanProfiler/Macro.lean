module

public meta import Lean
public import LeanProfiler.Timer
public import LeanProfiler.Summary

macro "profile" : term => `(profileEnd)

macro "profile " name:str " do" body:doSeq : term =>
  `(recordSpan $name do $body)
