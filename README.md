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

- An actor that has a single get method/property
- Fetch a value from an outside source (today I use Futures, but this will use an async function)
- Once fetched, cache it locally for better performance in subsequent requests
- Include a way to invalidate the locally cached value
- No concurrency warnings 
