// tdarrSkipTest
const details = () => ({
    id: 'Tdarr_Plugin_nxsv_GPU_Cleanup',
    Stage: 'Pre-processing',
    Name: 'GPU Transcode And Stream Cleanup',
    Type: 'Video',
    Operation: 'Transcode',
    Description: `Keeps one audio track each for the original language, English and
    undefined, removes subtitles and images, and orders video before audio in one pass.
    Encodes non-HEVC video with NVENC CQ 20, preset p6 and 4 B-frames. HEVC is copied.`,
    Version: '1.0',
    Tags: 'pre-processing,configurable',
    Inputs: [
        {
            name: 'sonarr_url',
            type: 'string',
            defaultValue: 'http://127.0.0.1:@sonarrPort@',
            inputUI: {type: 'text'},
            tooltip: 'Sonarr url, e.g. http://127.0.0.1:@sonarrPort@',
        },
        {
            name: 'sonarr_api_key',
            type: 'string',
            defaultValue: '',
            inputUI: {type: 'text'},
            tooltip: 'Sonarr api key (Settings > General).',
        },
        {
            name: 'radarr_url',
            type: 'string',
            defaultValue: 'http://127.0.0.1:@radarrPort@',
            inputUI: {type: 'text'},
            tooltip: 'Radarr url, e.g. http://127.0.0.1:@radarrPort@',
        },
        {
            name: 'radarr_api_key',
            type: 'string',
            defaultValue: '',
            inputUI: {type: 'text'},
            tooltip: 'Radarr api key (Settings > General).',
        },
    ],
});

const displayNames = new Intl.DisplayNames(['en'], {type: 'language'});

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
        {headers: {'X-Api-Key': apiKey}},
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
        preset: '',
        container: '.mkv',
        handBrakeMode: false,
        FFmpegMode: true,
        reQueueAfter: false,
        infoLog: '',
    };

    if (file.fileMedium !== 'video') return response;

    const video = file.ffProbeData.streams.filter((s) => s.codec_type === 'video'
        && !(s.disposition && s.disposition.attached_pic)
        && !['png', 'bmp', 'mjpeg'].includes(s.codec_name));
    if (video.length === 0) return response;

    const audio = file.ffProbeData.streams
        .filter((s) => s.codec_type === 'audio')
        .map((s, audioIndex) => ({
            audioIndex,
            index: s.index,
            lang: languageCode(s.tags && s.tags.language),
            channels: s.channels || 0,
            commentary: !!(s.disposition && s.disposition.comment),
        }));

    // Sonarr first: its parser only matches episode-style names, so movies fall through.
    const original = await arrParse(inputs.sonarr_url, inputs.sonarr_api_key, file.meta.FileName, 'series')
        || await arrParse(inputs.radarr_url, inputs.radarr_api_key, file.meta.FileName, 'movie');
    const originalCode = original && codeForArrName(original.name, audio.map((a) => a.lang));
    if (!originalCode) {
        response.infoLog += '☒Could not determine the original language. Keeping all audio. \n';
    }
    response.infoLog += `Original language: ${original ? original.name : 'unknown'} (${originalCode})\n`;

    const keepLangs = [originalCode, 'en', 'und'];
    const keep = new Set();
    keepLangs.forEach((lang) => {
        const best = audio
            .filter((a) => a.lang === lang)
            .sort((a, b) => a.commentary - b.commentary || b.channels - a.channels)[0];
        if (best) keep.add(best.audioIndex);
    });

    const selectedAudio = originalCode && keep.size > 0
        ? audio.filter((a) => keep.has(a.audioIndex)) : audio;
    const channelOrder = [8, 6, 2, 1];
    const rank = (channels) => channelOrder.includes(channels) ? channelOrder.indexOf(channels) : 4;
    selectedAudio.sort((a, b) => rank(a.channels) - rank(b.channels));
    const selected = [...video.map((s) => s.index), ...selectedAudio.map((a) => a.index)];
    const encode = video.some((s) => s.codec_name !== 'hevc');
    const changed = file.container !== 'mkv'
        || selected.length !== file.ffProbeData.streams.length
        || selected.some((index, position) => index !== file.ffProbeData.streams[position].index);
    if (!encode && !changed) {
        response.infoLog += '☑HEVC and streams already match the cleanup policy. \n';
        return response;
    }

    const {getNvdecHwaccelPreset} = require('../methods/nvdecPreset');
    const decode = encode ? getNvdecHwaccelPreset(file) : '';
    const codec = encode
        ? '-c:v hevc_nvenc -b:v 0 -preset p6 -cq 20 -rc-lookahead 32 -bf 4 -a53cc 0'
        : '-c:v copy';
    response.preset = `${decode}, ${selected.map((index) => `-map 0:${index}`).join(' ')} `
        + `-sn -dn ${codec} -c:a copy -max_muxing_queue_size 9999`;
    response.processFile = true;
    response.infoLog += `☑${encode ? 'NVENC transcode' : 'HEVC stream copy'} with stream cleanup. \n`;
    return response;
};

module.exports.details = details;
module.exports.plugin = plugin;
