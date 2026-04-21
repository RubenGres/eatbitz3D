// Local species data loader. Mirrors godot/Scripts/BitzAPI.gd.

let cache = { locale: null, data: null, promise: null };

export async function loadSpeciesData(locale) {
  if (cache.locale === locale && cache.data) return cache.data;
  if (cache.locale === locale && cache.promise) return cache.promise;
  cache.locale = locale;
  const file = locale === "pt" ? "data/species_data_pt.json" : "data/species_data_en.json";
  cache.promise = fetch(file)
    .then((r) => {
      if (!r.ok) throw new Error("Species data fetch failed: " + r.status);
      return r.json();
    })
    .then((json) => {
      cache.data = json;
      cache.promise = null;
      return json;
    });
  return cache.promise;
}

export async function getSpecies(locale, questId, speciesId) {
  const data = await loadSpeciesData(locale);
  const quest = data[questId];
  if (!quest) return null;
  const sp = quest[String(speciesId)];
  if (!sp) return null;
  return sp;
}
