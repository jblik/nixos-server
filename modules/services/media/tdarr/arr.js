const {readFileSync} = require('node:fs');
const {join} = require('node:path');

const apiKey = (app) => {
    const config = readFileSync(join(process.env.CREDENTIALS_DIRECTORY, `${app}.xml`), 'utf8');
    const match = config.match(/<ApiKey>\s*([^<]+?)\s*<\/ApiKey>/);
    if (!match) throw new Error(`Missing ApiKey in ${app} credential`);
    return match[1];
};

const notify = async (args, app) => {
    const {plugin} = require(process.env.TDARR_NOTIFY_PLUGIN);
    return plugin({
        ...args,
        inputs: {
            arr: app,
            arr_host: process.env[`${app.toUpperCase()}_URL`],
            arr_api_key: apiKey(app),
            unmonitor_after_refresh: false,
        },
    });
};

module.exports = {apiKey, notify};
