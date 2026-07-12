-- ═══ 🌐 COMMUNITY FEED — 2026-07-12 ═══
-- A per-coach community: clients (and the coach) post updates + photos and like
-- each other. Boosts engagement (AllInFit/Everfit-style social feed). Additive.

CREATE TABLE IF NOT EXISTS feed_posts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coach_email  text NOT NULL,          -- the community this post belongs to
  author_email text NOT NULL,
  author_name  text,
  content      text,
  image_url    text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_feed_posts ON feed_posts(coach_email, created_at DESC);

CREATE TABLE IF NOT EXISTS feed_likes (
  post_id    bigint NOT NULL REFERENCES feed_posts(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_email)
);

-- helper: is auth user a member of this coach's community (client or the coach)?
CREATE OR REPLACE FUNCTION _in_community(coach text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT coach = auth.email()
      OR EXISTS (SELECT 1 FROM clients c WHERE c.email = auth.email() AND c.coach_email = coach)
      OR auth.email() = 'halel1201@gmail.com';
$$;

ALTER TABLE feed_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fp_sel ON feed_posts;
CREATE POLICY fp_sel ON feed_posts FOR SELECT TO authenticated USING (_in_community(coach_email));
DROP POLICY IF EXISTS fp_ins ON feed_posts;
CREATE POLICY fp_ins ON feed_posts FOR INSERT TO authenticated WITH CHECK (author_email = auth.email() AND _in_community(coach_email));
DROP POLICY IF EXISTS fp_del ON feed_posts;
CREATE POLICY fp_del ON feed_posts FOR DELETE TO authenticated USING (author_email = auth.email() OR coach_email = auth.email() OR auth.email()='halel1201@gmail.com');

ALTER TABLE feed_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fl_sel ON feed_likes;
CREATE POLICY fl_sel ON feed_likes FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM feed_posts p WHERE p.id = feed_likes.post_id AND _in_community(p.coach_email)));
DROP POLICY IF EXISTS fl_cud ON feed_likes;
CREATE POLICY fl_cud ON feed_likes FOR ALL TO authenticated
  USING (user_email = auth.email()) WITH CHECK (user_email = auth.email());

SELECT 'community feed ready' AS r;
