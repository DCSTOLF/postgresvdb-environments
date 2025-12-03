-- Insert postgres-vdb-platform Component
INSERT INTO refresh_state (entity_id, entity_ref, unprocessed_entity, processed_entity, errors, next_update_at, last_discovery_at, location_key, result_hash, unprocessed_hash)
VALUES (
  'component:default/postgres-vdb-platform',
  'component:default/postgres-vdb-platform',
  '{"apiVersion":"backstage.io/v1alpha1","kind":"Component","metadata":{"name":"postgres-vdb-platform","title":"PostgreSQL VDB Platform","description":"GitOps platform for managing PostgreSQL Virtual Database environments using ArgoCD and Delphix","annotations":{"backstage.io/managed-by-location":"url:https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml","backstage.io/managed-by-origin-location":"url:https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml","backstage.io/techdocs-ref":"dir:.","argocd/app-name":"postgres-vdb-platform","github.com/project-slug":"DCSTOLF/postgresvdb-environments"},"tags":["postgres","database","gitops","argocd","delphix","vdb"],"links":[{"url":"https://argocd.k8s.delphixdemo.com/applications/postgres-vdb-platform","title":"ArgoCD - Platform","icon":"dashboard"},{"url":"https://github.com/DCSTOLF/postgresvdb-environments","title":"GitHub Repository","icon":"github"}],"namespace":"default"},"spec":{"type":"platform","lifecycle":"production","owner":"user:default/dcstolf"}}',
  NULL,
  '',
  NOW() + INTERVAL '1 hour',
  NOW(),
  'url:https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml',
  'manual-insert',
  'manual-insert'
) ON CONFLICT (entity_ref) DO UPDATE SET unprocessed_entity = EXCLUDED.unprocessed_entity;

-- Insert final_entities record
INSERT INTO final_entities (entity_id, hash, stitch_ticket, final_entity)
VALUES (
  'component:default/postgres-vdb-platform',
  'manual-insert',
  NULL,
  '{"apiVersion":"backstage.io/v1alpha1","kind":"Component","metadata":{"name":"postgres-vdb-platform","title":"PostgreSQL VDB Platform","description":"GitOps platform for managing PostgreSQL Virtual Database environments using ArgoCD and Delphix","annotations":{"backstage.io/managed-by-location":"url:https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml","backstage.io/managed-by-origin-location":"url:https://github.com/DCSTOLF/postgresvdb-environments/blob/main/catalog-info.yaml","backstage.io/techdocs-ref":"dir:.","argocd/app-name":"postgres-vdb-platform","github.com/project-slug":"DCSTOLF/postgresvdb-environments"},"tags":["postgres","database","gitops","argocd","delphix","vdb"],"links":[{"url":"https://argocd.k8s.delphixdemo.com/applications/postgres-vdb-platform","title":"ArgoCD - Platform","icon":"dashboard"},{"url":"https://github.com/DCSTOLF/postgresvdb-environments","title":"GitHub Repository","icon":"github"}],"namespace":"default","uid":"component:default/postgres-vdb-platform","etag":"manual-insert"},"spec":{"type":"platform","lifecycle":"production","owner":"user:default/dcstolf"},"relations":[{"type":"ownedBy","targetRef":"user:default/dcstolf"}]}'
) ON CONFLICT (entity_id) DO UPDATE SET final_entity = EXCLUDED.final_entity;
