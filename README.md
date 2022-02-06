# SerialUpdatingValue

Thread-safe access to a lazily retrieved value, with optional validity checking

## Motivation

Swift's Structured Concurrency provides many primitives, but lacks higher-level mechanics such as serial queues. This package is an investigation into how to reimplement that.

A recent Twitter thread inspired the investigation: https://twitter.com/layoutSubviews/status/1486925222137954304

> Swift Twitter, help me, you’re my only hope:
> With Swift Concurrency, is there an equivalent to a dispatch serial queue, 
> i.e. something on which `@Sendable () async -> Void` operations can be enqueued, and which executes them serially?

## Goals

Locally cache an auth token, providing concurrent access, lazy fetching, and re-fetching if no longer valid. 

- Using an `actor` for thread-safety 
- Generic over a `Value`
- Has a single getter method/property to get an up to date `Value`
- The value is fetched by a caller-defined async function
- Lazily fetch the first value upon first request
- While fetching, all subsequent requests must also await the fetch value
- Once fetched, cache it in-memory for faster performance in subsequent requests
- Include a way to invalidate the locally cached value, requiring the value to be re-fetched if invalid
- No concurrency warnings!

## Discussion

More discussion about this on the Swift Forums: https://forums.swift.org/t/rfc-using-swift-concurrency-as-a-serial-blocking-queue/55135
