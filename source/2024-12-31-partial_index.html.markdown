---
title: "Optimizing PostgreSQL with Partial Indexes in Rails"
date: 2024-12-31
tags: rails, postgres
---

# Optimizing PostgreSQL with Partial Indexes in Rails 

When our support team complained that abusive messages took too long to load, I dug into the issue and discovered that a partial index could dramatically improve performance. Here's how I approached the problem and implemented a fix using Rails and PostgreSQL.

## The Problem

> We run a messaging app where users can report abusive messages. Our support team regularly reviews flagged content, but the admin page showing unreviewed abusive messages was slow—it took over 20 seconds to load.


## Debugging Strategy

To fix the issue, I followed a standard performance workflow:

1. Confirm there's a problem
2. Reproduce it locally
3. Analyze and experiment with possible fixes
4. Implement the best one
5. Measure the result


## Confirm the Problem 

Logs showed that most of the time was spent on a single SQL query. I **added custom logging** to isolate it and monitor improvements later.
Adding the right metrics early in the process is important — it ensures that any optimization efforts can be validated effectively. 

## Reproduce Locally

I couldn't use the production dataset — it was 1TB. So I created a synthetic dataset using <span data-expand="docker_postgres_17" class="expander">Docker</span> and SQL.



[!note:docker_postgres_17]
```bash
docker run --platform linux/arm64 \
  --name postgres17 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=partial_blog \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -p 5417:5432 \
  -d postgres:17

```
[/!note:docker_postgres_17]


```sql
CREATE TABLE messages (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  author_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  is_abusive BOOLEAN NOT NULL,
  is_spam BOOLEAN NOT NULL,
  is_reviewed BOOLEAN NOT NULL,
  is_archived BOOLEAN NOT NULL
);

CREATE INDEX idx_messages_abusive_reviewed
  ON messages (is_abusive, is_spam, is_reviewed, is_archived);

```


## Generate Realistic Data

Initially, I generated 10M messages where:

- 1 in 10,000 were abusive
- 1 in 100,000 were spam
- 20% were archived
- 50% of abusive messages were reviewed

With this setup, the query ran fast (30ms), because PostgreSQL found matching rows quickly. But this didn't reflect production behavior.

So I made the data sparser — 1 abusive message per 1 million rows—and now the query took 250–400ms. Much more realistic.

## Analyze

PostgreSQL wasn't using any indexes for the query:

```sql
SELECT * FROM messages
WHERE is_abusive = TRUE AND is_reviewed = FALSE
ORDER BY created_at DESC LIMIT 5;
```

Why? Because boolean fields have low cardinality, so PostgreSQL skipped existing indexes and performed a full sequential scan.


## Experimenting with Indexes

### Experiment 1: Composite Index on Booleans

```sql
CREATE INDEX idx_all_booleans
  ON messages (is_abusive, is_spam, is_reviewed, is_archived);
```

No effect. Postgres still used a sequential scan due to low selectivity.



### Experiment 2: Partial Index

```sql
CREATE INDEX messages_needing_review_idx
  ON messages (id, created_at)
  WHERE is_abusive = TRUE OR is_spam = TRUE;
```

This index only includes rows that actually need reviewing.
Result: Query time dropped to 5ms. That’s a 30x improvement.
PostgreSQL now used an index scan:

```sql
-> Index Scan using messages_needing_review_idx ...
```


## Rails Implementation

Rails supports partial indexes natively:

```rb
add_index :messages, [:id, :created_at],
          name: "messages_needing_review_idx",
          where: "is_abusive = TRUE OR is_spam = TRUE",
          algorithm: :concurrently
```

The all magic happens in the `where` clause. The index will be written to only when the filter condition is true.

## Measure & consolidate

I reran the query in production and confirmed that performance was fixed.

To future-proof this, I added a test to ensure the query planner continues to use our index:


```ruby
  it "uses the partial index" do
    expect(query.explain).to include('Index Scan using messages_needing_review_idx')
  end
```
You might also consider creating a PostgreSQL view to lock the query shape to the index.


### A Word of Caution
- Partial indexes only help if the filter condition matches exactly.
- They also increase write overhead (as any index), so use them only when needed.

## Conclusion

In summary, creating a partial index on my `messages` table significantly improved query performance.
This one optimization took our query from 400ms to 5ms.
