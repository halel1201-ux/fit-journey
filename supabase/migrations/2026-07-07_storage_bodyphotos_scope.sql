-- scope body-photos storage objects: owner (folder[1]=email) + their coach + admin
DROP POLICY IF EXISTS bphotos_select ON storage.objects;
DROP POLICY IF EXISTS bphotos_insert ON storage.objects;
DROP POLICY IF EXISTS bphotos_delete ON storage.objects;
CREATE POLICY bphotos_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='body-photos' AND (
    (storage.foldername(name))[1] = (auth.jwt()->>'email')
    OR EXISTS (SELECT 1 FROM public.clients c WHERE c.email=(storage.foldername(name))[1] AND c.coach_email=(auth.jwt()->>'email'))
    OR auth.email()='halel1201@gmail.com'));
CREATE POLICY bphotos_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='body-photos' AND (
    (storage.foldername(name))[1] = (auth.jwt()->>'email')
    OR EXISTS (SELECT 1 FROM public.clients c WHERE c.email=(storage.foldername(name))[1] AND c.coach_email=(auth.jwt()->>'email'))
    OR auth.email()='halel1201@gmail.com'));
CREATE POLICY bphotos_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id='body-photos' AND (
    (storage.foldername(name))[1] = (auth.jwt()->>'email')
    OR EXISTS (SELECT 1 FROM public.clients c WHERE c.email=(storage.foldername(name))[1] AND c.coach_email=(auth.jwt()->>'email'))
    OR auth.email()='halel1201@gmail.com'));
