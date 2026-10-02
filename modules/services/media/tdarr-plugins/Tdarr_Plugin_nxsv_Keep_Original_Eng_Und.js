// tdarrSkipTest
const details = () => ({
  id: 'Tdarr_Plugin_nxsv_Keep_Original_Eng_Und',
  Stage: 'Pre-processing',
  Name: 'Keep Original Language, English And Undefined Audio',
  Type: 'Audio',
  Operation: 'Transcode',
  Description: `Looks up the original language in Sonarr, then Radarr, and keeps one audio
    track each for the original language, English and undefined (at most 3). Within a
    language the non-commentary track with the most channels wins. Skips the file if the
    original language can't be determined.`,
  Version: '1.0',
  Tags: 'pre-processing,configurable',
  Inputs: [
    {
      name: 'sonarr_url',
      type: 'string',
      defaultValue: 'http://127.0.0.1:8989',
      inputUI: { type: 'text' },
      tooltip: 'Sonarr url, e.g. http://127.0.0.1:8989',
    },
    {
      name: 'sonarr_api_key',
      type: 'string',
      defaultValue: '',
      inputUI: { type: 'text' },
      tooltip: 'Sonarr api key (Settings > General).',
    },
    {
      name: 'radarr_url',
      type: 'string',
      defaultValue: 'http://127.0.0.1:7878',
      inputUI: { type: 'text' },
      tooltip: 'Radarr url, e.g. http://127.0.0.1:7878',
    },
    {
      name: 'radarr_api_key',
      type: 'string',
      defaultValue: '',
      inputUI: { type: 'text' },
      tooltip: 'Radarr api key (Settings > General).',
    },
  ],
});

const displayNames = new Intl.DisplayNames(['en'], { type: 'language' });

const languageCode = (tag) => {
  if (!tag) return 'und';
  try {
    // Canonicalising maps ISO 639-2/B tags like ger/fre/chi onto de/fr/zh.
    return Intl.getCanonicalLocales(tag)[0].split('-')[0];
  } catch (err) {
    return 'und';
  }
};

// Radarr/Sonarr only expose the language's English name, e.g. "Portuguese (Brazil)".
const codeForArrName = (name, candidates) => {
  const base = (name || '').replace(/\s*\(.*\)$/, '').replace(/^Flemish$/, 'Dutch');
  if (!base || ['Unknown', 'Any', 'Original'].includes(base)) return null;
  return candidates.find((code) => code !== 'und'
    && (displayNames.of(code) || '').startsWith(base)) || base;
};

const arrParse = async (url, apiKey, fileName, key) => {
  if (!apiKey) return null;
  const res = await fetch(
    `${url.replace(/\/$/, '')}/api/v3/parse?title=${encodeURIComponent(fileName)}`,
    { headers: { 'X-Api-Key': apiKey } },
  );
  if (!res.ok) throw new Error(`${url} parse failed: HTTP ${res.status}`);
  const body = await res.json();
  return body[key] ? body[key].originalLanguage : null;
};

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const plugin = async (file, librarySettings, inputs, otherArguments) => {
  const lib = require('../methods/lib')();
  // eslint-disable-next-line no-param-reassign
  inputs = lib.loadDefaultValues(inputs, details);
  const response = {
    processFile: false,
    preset: ', -map 0 ',
    container: `.${file.container}`,
    handBrakeMode: false,
    FFmpegMode: true,
    reQueueAfter: false,
    infoLog: '',
  };

  const audio = file.ffProbeData.streams
    .filter((s) => s.codec_type === 'audio')
    .map((s, audioIndex) => ({
      audioIndex,
      lang: languageCode(s.tags && s.tags.language),
      channels: s.channels || 0,
      commentary: !!(s.disposition && s.disposition.comment),
    }));

  // Sonarr first: its parser only matches episode-style names, so movies fall through.
  const original = await arrParse(inputs.sonarr_url, inputs.sonarr_api_key, file.meta.FileName, 'series')
    || await arrParse(inputs.radarr_url, inputs.radarr_api_key, file.meta.FileName, 'movie');
  const originalCode = original && codeForArrName(original.name, audio.map((a) => a.lang));
  if (!originalCode) {
    response.infoLog += '☒Could not determine the original language. Skipping. \n';
    return response;
  }
  response.infoLog += `Original language: ${original.name} (${originalCode})\n`;

  const keepLangs = [originalCode, 'en', 'und'];
  const keep = new Set();
  keepLangs.forEach((lang) => {
    const best = audio
      .filter((a) => a.lang === lang)
      .sort((a, b) => a.commentary - b.commentary || b.channels - a.channels)[0];
    if (best) keep.add(best.audioIndex);
  });

  const remove = audio.filter((a) => !keep.has(a.audioIndex));
  if (keep.size === 0) {
    response.infoLog += '☒No original, English or undefined audio track. Skipping. \n';
    return response;
  }
  if (remove.length === 0) {
    response.infoLog += '☑No audio tracks to remove. \n';
    return response;
  }

  remove.forEach((a) => { response.preset += `-map -0:a:${a.audioIndex} `; });
  response.preset += '-c copy -max_muxing_queue_size 9999';
  response.processFile = true;
  response.infoLog += `☑Removing audio tracks: ${remove.map((a) => `${a.audioIndex} (${a.lang})`).join(', ')} \n`;
  return response;
};

module.exports.details = details;
module.exports.plugin = plugin;
