-- Deploy guix-data-service:git_repositories to pg
-- requires: initial_import

BEGIN;

CREATE TABLE git_repositories (
    id integer PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY,
    label character varying,
    url character varying NOT NULL UNIQUE
);

INSERT INTO git_repositories (url)
SELECT DISTINCT url FROM guix_revisions;

-- Change the guix_revisions table

ALTER TABLE guix_revisions ADD COLUMN git_repository_id integer
REFERENCES git_repositories (id);

UPDATE guix_revisions SET git_repository_id = (
  SELECT id FROM git_repositories WHERE guix_revisions.url = git_repositories.url
);

ALTER TABLE guix_revisions ALTER COLUMN git_repository_id SET NOT NULL;

ALTER TABLE guix_revisions DROP COLUMN url;

-- Change the load_new_guix_revision_jobs table

ALTER TABLE load_new_guix_revision_jobs ADD COLUMN git_repository_id integer
REFERENCES git_repositories (id);

UPDATE load_new_guix_revision_jobs SET git_repository_id = (
  SELECT id FROM git_repositories WHERE load_new_guix_revision_jobs.url = git_repositories.url
);

ALTER TABLE load_new_guix_revision_jobs ALTER COLUMN git_repository_id SET NOT NULL;

ALTER TABLE load_new_guix_revision_jobs DROP COLUMN url;

COMMIT;