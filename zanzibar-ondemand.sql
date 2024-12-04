CREATE TABLE relation(
    id INT NOT NULL PRIMARY KEY,
    name VARCHAR NOT NULL
) WITH (
    'materialized' = 'true',
    'connectors' = '[{
      "transport": {
        "name": "datagen",
        "config": {
            "plan": [{
                "limit": 3,
                "fields": {
                    "id": { "values": [1, 2, 3] },
                    "name": { "values": ["PARENT", "OWNER", "MEMBER"] }
                }
            }]
        }
      }
    }]'
);

CREATE TABLE rules (
    id INT NOT NULL PRIMARY KEY,
    path_relation VARCHAR NOT NULL,
    edge_relation VARCHAR NOT NULL,
    derived_relation VARCHAR NOT NULL
) WITH (
    'materialized' = 'true',
    'connectors' = '[{
      "transport": {
        "name": "datagen",
        "config": {
            "plan": [{
                "limit": 4,
                "fields": {
                    "path_relation": { "values": ["PARENT", "OWNER", "MEMBER", "MEMBER"] },
                    "edge_relation": { "values": ["PARENT", "PARENT", "MEMBER", "OWNER"] },
                    "derived_relation": { "values": ["PARENT",  "OWNER", "MEMBER", "OWNER"] }
                }
            }]
        }
      }
    }]'
);


CREATE TABLE object_edges(
    object1 BIGINT NOT NULL,
    object2 BIGINT NOT NULL,
    relation INT NOT NULL
) WITH (
    'materialized' = 'true',
    -- A three-level directory tree
    -- 1 top-level folder
    -- 10000 second-level folders
    -- 1,000,000 third-level subfolders
    -- 1000 groups that own 5 second-level folders each
    'connectors' = '[{
      "transport": {
        "name": "datagen",
        "config": {
            "plan": [
            {
                "limit": 10000,
                "fields": {
                    "object1": { "values": [0] },
                    "object2": { "range": [1, 10001] },
                    "relation": { "values": [1] }
                }
            },
            {
                "limit": 1000000,
                "fields": {
                    "object1": { "range": [1, 10001] },
                    "object2": { "range": [10001, 1010001] },
                    "relation": { "values": [1] }
                }
            },
            {
                "limit": 5000,
                "fields": {
                    "object1": { "range": [10000001, 10001001] },
                    "object2": { "range": [1, 10001] },
                    "relation": { "values": [2] }
                }
            }]
        }
      }
    }]'
);


CREATE TABLE user_edges(
    id BIGINT NOT NULL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    object_id BIGINT NOT NULL,
    relation INT NOT NULL
) WITH (
    'materialized' = 'true',
    -- 1000 users with 10 random groups per user. The datagen will run
    -- continuously, constantly updating group membership.
    'connectors' = '[{
      "transport": {
        "name": "datagen",
        "config": {
            "plan": [{
                "fields": {
                    "id": {"range": [0, 100000]},
                    "user_id": { "range": [100000001, 100010001] },
                    "object_id": { "range": [10000001, 10010001], "strategy": "uniform" },
                    "relation": { "values": [3] }

                }
            }]
        }
      }
    }]'

);

-- Resolve relation names into id's in rules.
CREATE MATERIALIZED VIEW resolved_rules AS
SELECT
    rel1.id as path_relation,
    rel2.id as edge_relation,
    rel3.id as derived_relation
FROM rules
JOIN relation as rel1 on rules.path_relation = rel1.name
JOIN relation as rel2 on rules.edge_relation = rel2.name
JOIN relation as rel3 on rules.derived_relation = rel3.name;

-- The set of user/object pairs to monitor.
CREATE TABLE subscriptions (
    id BIGINT NOT NULL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    object_id BIGINT NOT NULL
) WITH (
    'materialized' = 'true',
    -- Generate 50,000 continuously changing subscriptions.
    'connectors' = '[{
      "transport": {
        "name": "datagen",
        "config": {
            "plan": [{
                "fields": {
                    "id": {"range": [0, 50000]},
                    "user_id": { "range": [100000001, 100010001] },
                    "object_id": { "range": [10001, 1010001], "strategy": "uniform" }
                }
            }]
        }
      }
    }]'

);

-- Subset of edges relevant to maintaining subscriptions. 
DECLARE RECURSIVE VIEW relevant_edges (
    object1 BIGINT NOT NULL,
    object2 BIGINT NOT NULL,
    relation INT NOT NULL
);

CREATE MATERIALIZED VIEW relevant_edges AS
-- Base of recursion:
-- * all edges leading to subscribed objects
-- * all output edges connected to subscribed users
(SELECT object_edges.*
 FROM object_edges JOIN subscriptions ON object_edges.object2 = subscriptions.object_id)
UNION ALL
(SELECT
    user_edges.user_id as object1,
    user_edges.object_id as object2,
    relation 
 FROM user_edges JOIN subscriptions ON user_edges.user_id = subscriptions.user_id)
UNION ALL
-- Step of recursion: add all predecessors of the relevant edges computed so far.
(SELECT object_edges.* 
 FROM object_edges JOIN relevant_edges ON object_edges.object2 = relevant_edges.object1);

-- Compute transitiove closure of `rules` over `relevant_edges`.
DECLARE RECURSIVE VIEW relationships (
    object1 BIGINT NOT NULL,
    object2 BIGINT NOT NULL,
    relation INT NOT NULL
);

CREATE MATERIALIZED VIEW suffixes AS
SELECT
    resolved_rules.path_relation,
    resolved_rules.derived_relation,
    relevant_edges.object1,
    relevant_edges.object2
FROM
    resolved_rules JOIN relevant_edges on resolved_rules.edge_relation = relevant_edges.relation;

CREATE MATERIALIZED VIEW relationships
AS
    SELECT * FROM relevant_edges
    UNION ALL
    SELECT
        relationships.object1 as object1,
        suffixes.object2 as object2,
        suffixes.derived_relation as relation
    FROM
        relationships
        JOIN suffixes ON relationships.relation = suffixes.path_relation AND relationships.object2 = suffixes.object1;

CREATE MATERIALIZED VIEW notifications
AS
SELECT
    relationships.*
FROM
    relationships JOIN subscriptions
ON relationships.object1 = subscriptions.user_id AND relationships.object2 = subscriptions.object_id;


