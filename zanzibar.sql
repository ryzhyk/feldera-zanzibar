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
    userid BIGINT NOT NULL,
    objectid BIGINT NOT NULL,
    relation INT NOT NULL
) WITH (
    'materialized' = 'true',
    -- 1000 users with 3 random groups per user. The datagen will run
    -- continuously, constantly updating group membership.
    'connectors' = '[{
      "max_batch_size": 3000,
      "transport": {
        "name": "datagen",
        "config": {
            "plan": [{
                "fields": {
                    "id": {"range": [0, 50000]},
                    "userid": { "range": [100000001, 100010001] },
                    "objectid": { "range": [10000001, 10001001], "strategy": "uniform" },
                    "relation": { "values": [3] }
                }
            }]
        }
      }
    }]'

);

CREATE MATERIALIZED VIEW edges AS
SELECT
    userid as object1,
    objectid as object2,
    relation
FROM user_edges
UNION ALL SELECT * FROM object_edges;

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

-- Compute transitive closure of `rules` over the object-relation graph
-- defined by `edges`.
CREATE RECURSIVE VIEW relationships (
    object1 BIGINT NOT NULL,
    object2 BIGINT NOT NULL,
    relation INT NOT NULL
);

CREATE MATERIALIZED VIEW suffixes AS
SELECT
    resolved_rules.path_relation,
    resolved_rules.derived_relation,
    edges.object1,
    edges.object2
FROM
    resolved_rules JOIN edges on resolved_rules.edge_relation = edges.relation;

CREATE MATERIALIZED VIEW relationships
AS
    SELECT * FROM edges
    UNION ALL
    SELECT
        relationships.object1 as object1,
        suffixes.object2 as object2,
        suffixes.derived_relation as relation
    FROM
        relationships
        JOIN suffixes ON relationships.relation = suffixes.path_relation AND relationships.object2 = suffixes.object1;
