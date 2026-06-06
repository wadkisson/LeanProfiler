module

public meta import Lean
public import LeanProfiler.Timer
public import LeanProfiler.Summary

macro "profile " name:str " do" body:doSeq : term =>
  `(recordSpan $name do $body)

macro "profile " x:term : term => `(profileReturn $x)

macro "profile" : term => `(profileEnd)
