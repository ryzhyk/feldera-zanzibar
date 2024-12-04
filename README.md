# Implementation of a simplified Zanzibar authorization model in Feldera

This repository contains two implementations of the authorization model from the
Zanzibar paper using Feldera.

## Authorization model

* **Relations:** Model relations between entities, e.g., OWNER, PARENT, MEMBER,
  etc.

* **Rules:** In this example we model binary rules of the form "if there is a
  relation R1 between objects O1 and O2, and a relation R2 between objects O2
  and O3, then there is a relation R3 betweeb O1 and O3".

* **Object graph:** Models the set of relationships provided as input to the
  system.  Serves as the starting point for evaluating authorization rules.

## The naive implementation

The naive implementation incrementally computes **ALL** relationships that can
be derived from the object graph by applying rules transitively.

We model not only objects and relations, but also rules, as SQL tables. As a
result, the user can change both the object graph and the set of rules
dynamically.

The model uses recursive SQL queries to evaluate the rules transitively up to an
arbitrary depth.

## Optimized implementation

The main issue with the naive model is that it can generate a polynomial number
of relationships.  Consider a system with 1M users and a public folder with 1M
files. These objects alone will generate 1 trillion relationships, most of which
are irrelevant at any given time.

There are many ways to optimize this computation, depending on the use case.
Let's assume that the system is able to identify the set of users and objects of
interest and communicate them to Feldera in the form of subscriptions, i.e.,
(`user`, `object`) pairs, where the system would like to monitor `user`'s access
rights to `object`.

Given a set of subscriptions, we can narrow down the object graph to only
relevant edges that can be part of a path from a subscribed user to a
subscribed-to object.

The `zanzibar-ondemand.sql` program adds this optimization to the naive
implementation above.  In addition to a stream of changes to the object graph,
it maintains a constantly changing set of 10000 subscriptions.  This
implementations runs ~100x faster and uses 10x less memory than the naive
implementation.

## How to run

Simply paste the code from one of the SQL files in this repository to the
Feldera WebConsole and click Start.  Both models come with a preconfigured
random data generator, which will feed a continuous stream of changes to the
Feldera pipeline.
