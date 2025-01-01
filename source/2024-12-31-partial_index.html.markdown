---
title: "Using Partial Indexes in Rails"
date: 2024-12-31
tags: rails, postgres
---

### Introduction

In this post, I will share the insights I gained and the steps I followed to optimize the performance of a PostgreSQL query on a large table by creating a partial index.

I was working on improving the speed of a query while keeping my database lightweight and efficient, and I found partial indexing to be an effective solution.

### Use case

> Let’s assume we are running a messaging app where `users` can send messages to each others. On some occasions, our AI detection will flag some flags are `abusive` and our support team need to review these messages.
> Support team complains the list of abusive message they need to review takes a lot of time to load.

### Methodology

My approach to resolve this issue is the same it would be like fixing any performance bug:

1. Confirm there is a issue - measure
2. re-produce the problem in a consistent way on my local machine
3. analyse, experiment, and implement
4. deploy
5. Check the benefit - measure.

The greater difficulty in our journey will lie in step 2.  Fixing a performance issue without measuring is a mistake: often, your intuition will be wrong, and you will optimise the wrong thing.

So lets go !

## 1. Confirm there is a problem - measure

Confirming there was a problem was pretty easy. By navigating to the page using the query, I could easily verify that a loader is displayed for 20 seconds.

A quick look at our logs and I could already see that most of the time was spend in sql.

At this point, I decided to add an extra log to production, to narrow down to the exact problematic query. This way, we can measure and verify later that whatever optimization we came up with actually had some effect.

## 2. Finding a way to make the bug appear in local

The simplest and most effective approach would have been to copy the production data to my disk and work from that. However, the `messages` table is approximately 1TB, with several indexes exceeding 100GB each. So, using the production data wasn’t a handy solution,and I had to create some sample data instead.

### Setting up my local database

In this section I will setup a local postgres and generate some random data using a sql query. I need to generate enough data to have the issue arise.

- setup a test db

```bash
docker run --platform linux/arm64 \
  --name postgres17 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=partial_blog \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -p 5417:5432 \
  -d postgres:17

```

- create the messages table and some indexes

```sql
DROP TABLE IF EXISTS messages ;

CREATE TABLE messages (
    id SERIAL PRIMARY KEY,           
    created_at TIMESTAMP NOT NULL,   
    updated_at TIMESTAMP NOT NULL,   
    author_id INTEGER NOT NULL,      
    content TEXT NOT NULL,           
    is_abusive BOOLEAN NOT NULL,        -- Whether the message is abusive
    is_spam  BOOLEAN NOT NULL,
    is_reviewed BOOLEAN NOT NULL,       -- Whether the message has been reviewed by support team
    is_archived BOOLEAN NOT NULL
);

CREATE INDEX idx_messages_created_at ON messages (created_at);
CREATE INDEX idx_messages_author_created_at ON messages (author_id, created_at);
CREATE INDEX idx_messages_abusive_reviewed ON messages (is_abusive, is_spam, is_reviewed, is_archived);
```


Now that my postgres db is up an running, it’s time to populate my `messages` table with some data. To do that we will use a sql script, that will generate 10 millions messages.

I decided to generate messages with the following spread :

### dataset configuration #1

`is_abusive` : 1 in 10,000

`is_spam` : 1 in 100,000

`is_archived` : 20%

`is_reviewed` : 50% of those needing review

- sql

    ```sql
    TRUNCATE messages;
    
    WITH existing_max_id AS (
    	SELECT
    		coalesce(max(id), 0) AS max_id
    	FROM
    		messages
    ),
    random_data AS (
    	SELECT
    		(existing_max_id.max_id + row_number() OVER ()) AS id,
    		now() - INTERVAL '2 months' + (gs * INTERVAL '40 seconds') AS created_at,
    		(random() < 0.0001) AS is_abusive,
    		(random() < 0.00001) AS is_spam,
    		(random() < 0.2) AS is_archived,
    		'Generated content: ' || substring(md5(random()::text) || md5(random()::text)
    	FROM 1 FOR (10 + (random() * 50)::int)) AS content -- Random content size
    	FROM
    		generate_series(1, 10000000) AS gs,
    		existing_max_id)
    	INSERT INTO messages (id, created_at, updated_at, author_id, content, is_abusive, is_spam, is_reviewed, is_archived)
    	SELECT
    		id,
    		created_at,
    		created_at AS updated_at,
    		id % 100 + 1 AS author_id, -- Example: author_id based on id (modify as needed)
    		content,
    		is_abusive,
    		is_spam,
    		CASE WHEN (is_abusive OR is_spam) THEN
    			(random() < 0.5) -- 50% of abusive have been reviewed
    		ELSE
    			FALSE -- Always false if not abusive
    		END AS is_reviewed,
    		is_archived
    	FROM
    		random_data;
    
    ```


On my recent laptop it takes about a minute to populate.

- Populate with some data: 1% of abusive messages

  My first approach was pretty naive:

```sql
WITH existing_max_id AS (
    SELECT COALESCE(MAX(id), 0) AS max_id FROM messages 
),
random_data AS (
    SELECT 
        (existing_max_id.max_id + row_number() OVER ()) AS id,  
        NOW() - INTERVAL '2 months' + (gs * INTERVAL '40 seconds') AS created_at,
        (random() < 0.01) AS abusive,  -- 1% chance of being abusive
        CASE 
            WHEN (random() < 0.01) THEN (random() < 0.5)  -- 50% of abusive have been reviewed
            ELSE FALSE  -- Always false if not abusive
        END AS reviewed,
        'Generated content: ' || substring(md5(random()::text) || md5(random()::text) FROM 1 FOR (10 + (random() * 50)::int)) AS content  -- Random content size
    FROM generate_series(1, 10000000) AS gs,
         existing_max_id
)
INSERT INTO messages (
    id,
    created_at,
    updated_at,
    author_id,
    content,
    abusive,
    reviewed
)
SELECT 
    id,
    created_at,
    created_at AS updated_at,
    id % 100 + 1 AS author_id,  -- Example: author_id based on id (modify as needed)
    content,
    abusive,
    reviewed
FROM random_data;

```


When we to try to retrieve the abusive which hasn’t been reviewed yet, we notice the query is pretty fast: 30ms.
Let’s find out what is going on here, by explaining the query plan.
It appears that postgres only had to examine only 189k rows.

That’s because my created data has “too many” errors row, postgres will find the 100 rows very quickly, and doesn’t need to examine too much data.

### dataset  configuration #2

So I decided to make the data a lot more sparse, and went for 1 abusive  message  every 1 million (instead of 1 every 100).

And now, running the query takes a lot more time: around 250ms. And remember, my test database is around 2GB when my production database is 1TB.

- Query plan when there is  1 abusive message every  1 million and 20 millions messages ⇒ 400ms

```bash
    
    Limit  (cost=371054.44..371054.45 rows=1 width=80) (actual time=368.576..370.384 rows=5 loops=1)
      Output: id, created_at, updated_at, author_id, content, abusive, reviewed
      Buffers: shared hit=192 read=286529
      ->  Sort  (cost=371054.44..371054.45 rows=1 width=80) (actual time=363.242..365.050 rows=5 loops=1)
            Output: id, created_at, updated_at, author_id, content, abusive, reviewed
            Sort Key: messages.created_at DESC
            Sort Method: quicksort  Memory: 26kB
            Buffers: shared hit=192 read=286529
            ->  Gather  (cost=1000.00..371054.43 rows=1 width=80) (actual time=111.675..365.023 rows=8 loops=1)
                  Output: id, created_at, updated_at, author_id, content, abusive, reviewed
                  Workers Planned: 2
                  Workers Launched: 2
                  Buffers: shared hit=192 read=286529
                  ->  Parallel Seq Scan on public.messages  (cost=0.00..370054.33 rows=1 width=80) (actual time=135.916..342.357 rows=3 loops=3)
                        Output: id, created_at, updated_at, author_id, content, abusive, reviewed
                        Filter: (messages.abusive AND (NOT messages.reviewed))
                        Rows Removed by Filter: 6666664
                        Buffers: shared hit=192 read=286529
                        Worker 0:  actual time=3.828..332.174 rows=4 loops=1
                          JIT:
                            Functions: 2
                            Options: Inlining false, Optimization false, Expressions true, Deforming true
                            Timing: Generation 0.143 ms (Deform 0.099 ms), Inlining 0.000 ms, Optimization 0.165 ms, Emission 2.848 ms, Total 3.157 ms
                          Buffers: shared hit=65 read=102685
                        Worker 1:  actual time=292.653..332.188 rows=1 loops=1
                          JIT:
                            Functions: 2
                            Options: Inlining false, Optimization false, Expressions true, Deforming true
                            Timing: Generation 0.134 ms (Deform 0.079 ms), Inlining 0.000 ms, Optimization 0.172 ms, Emission 2.849 ms, Total 3.154 ms
                          Buffers: shared hit=64 read=102368
    Planning Time: 0.177 ms
    JIT:
      Functions: 7
      Options: Inlining false, Optimization false, Expressions true, Deforming true
      Timing: Generation 0.820 ms (Deform 0.448 ms), Inlining 0.000 ms, Optimization 0.701 ms, Emission 10.675 ms, Total 12.196 ms
    Execution Time: 371.023 ms
```


We reach our goal: generating a dataset that will let the performance issue arise.

## 3. Analyse and experiment

In the previous section, we noticed that data scarcity has a significant impact on performance. But what causes this? What’s going on?

In both scenarios, the query planner is not using any index, leading it to examine each row sequentially until it identifies 100 rows that meet our filter criteria. Once it finds those 100 rows, it stops and returns the results.

In the first scenario, where the sample data contains a high number of `abusive = TRUE` rows, PostgreSQL can still locate the relevant rows relatively quickly, albeit inefficiently.

On the opposite, in the second scenario, where there is only one matching row for every million, PostgreSQL must scan nearly the entire database to retrieve just five rows, which takes considerably more time.

Before moving on, I want to copy the database we obtained earlier, especially since we’ll be experimenting with creating indexes and other modifications. This approach allows me to establish a clear reference for my tests: one database reflecting the existing issues and another focused on performance optimisation.

### Experiment 1: add every booleans in an index

A first idea would be to create missing indexes. In my experience, many performance issues occurring in small to medium sized team are missing indexes. So the first thing I would look for is a column missing an index.

In our case, every column appearing in the filter clause has it’s own index. But what if we had an index covering all the columns ? Let’s try that !

Result: it didn’t help: boolean column cardinality is very low, and index are not optimised for low cardinality. Query planner will not choose this index

TODO: Check the result. Check the disk usage.

### Experiment 2:  partial index

A partial index is a specialised index that will only index some rows matching a filter.

```sql
CREATE INDEX messages_needing_review_idx
ON messages (id, created_at)
WHERE is_abusive = TRUE or is_spam = TRUE;
```

This index focuses only on rows which are `is_abusive = TRUE` or `is_spam = TRUE`

The filtering is performed at “write time” when new rows are inserted / updated / deleted.

Now , the query is executed in `5ms`  which is  30x faster than the initial query.

It look like we have a serious candidate  for our performance issue.

---

```sql
->  Index Scan using messages_needing_review_idx on messages  (cost=0.28..1798.15 rows=802 width=83)
```

---

### Implementation in rails

Now that we have found an index definition that helped us improving our query, let’s add it to our production database. It’s pretty easy, rails migration DSL can already handle partial indexes :

```jsx
    add_index :messages, [ :id, :created_at ],
              where: "is_abusive = TRUE or is_spam = TRUE",
              name: "messages_needing_review_idx",
              algorithm: :concurrently
```

The all magic happens in the `where` clause. The index will be written to only when the filter condition is true.

## **Measure & consolidate**

Running the query in production confirmed our issue was fixed. Using the measure we implemented in the first section was a good confirmation your partial index helped.

Partial indexes are fragile, and if the condition changes, i.e. the filter condition evolves, the query planner won’t may not be able to use the query planner anymore, and as a result the same bug may re-appear in the future.

I want to ensure that future developers, using this query will consistently hit the index. I need to find a way to add coupling between the query and the index.

TODO: specs

---

### **Conclusion**

In summary, creating a partial index on my `messages` table was a great and efficient way to reduce that significantly improved query performance. This approach reduced the overhead of indexing while focusing on the most relevant data for my queries.

Keep in mind that adding an index  will add write overhead (otherwise we would add indexes for every single query).
