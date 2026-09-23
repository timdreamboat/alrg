// ============================================================
// ALRG configuration — the ONLY file you ever edit by hand.
// Paste the two values from Supabase → Project Settings → API.
// ============================================================
window.ALRG_CONFIG = {
  SUPABASE_URL: "https://cllcfkizaalvbjtevqpf.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNsbGNma2l6YWFsdmJqdGV2cXBmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAwODY4NjYsImV4cCI6MjEwNTY2Mjg2Nn0.LAkZVmEeJ7j7fEcxakMTz1A-nUVbwS8pdSLE7GIBYCY",

  // Optional. Leave blank to stay on the free map (Esri tiles +
  // Nominatim geocoding) — that's the default and costs nothing. Paste
  // a real Mapbox access token here ONLY once you've actually created
  // a paid Mapbox subscription, and the app automatically switches to
  // Mapbox tiles + Mapbox Geocoding, no other changes needed. See
  // pipeline/PAID_UPGRADE_POINTS.md #1/#2 for why this exists and what
  // it upgrades. Get a token at mapbox.com/account/access-tokens.
  MAPBOX_TOKEN: ""
};
