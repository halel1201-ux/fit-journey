-- ═══ 🔎 FOOD RETRIEVAL RPC — 2026-07-12 ═══
-- Ranks food_reference rows by how many query words appear in the name
-- (word-overlap), tie-broken by shorter/more-generic name. Used by the autopilot
-- to pull only the foods relevant to a client's question.
-- NOTE: splits words with plain ASCII-punctuation regex only — locale character
-- classes ([:alnum:], א-ת ranges) behave differently on the PostgREST pooled
-- connection and were silently stripping Hebrew.

CREATE OR REPLACE FUNCTION search_food(q text, lim int DEFAULT 10)
RETURNS TABLE(name text, kcal int, protein numeric, carbs numeric, fat numeric, hits int)
LANGUAGE sql STABLE AS $$
  WITH ws AS (
    SELECT DISTINCT w FROM unnest(
      string_to_array(regexp_replace(coalesce(q,''), '[,.?!;:()\[\]"''/\\-]+', ' ', 'g'), ' ')
    ) w
    WHERE length(w) >= 2
  )
  SELECT f.name, f.kcal, f.protein, f.carbs, f.fat,
    (SELECT count(*)::int FROM ws WHERE f.name ILIKE '%'||ws.w||'%') AS hits
  FROM food_reference f
  WHERE EXISTS (SELECT 1 FROM ws WHERE f.name ILIKE '%'||ws.w||'%')
  ORDER BY hits DESC, char_length(f.name) ASC
  LIMIT lim;
$$;
GRANT EXECUTE ON FUNCTION search_food(text,int) TO anon, authenticated, service_role;

SELECT 'search_food rpc ready' AS r;
