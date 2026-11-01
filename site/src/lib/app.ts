import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/** The app version, read from the Xcode project at build time, so the site never falls behind a release. */
export const appVersion: string = (() => {
  const yml = readFileSync(resolve(process.cwd(), '../project.yml'), 'utf8');
  const match = yml.match(/MARKETING_VERSION:\s*"?([\d.]+)"?/);
  if (!match?.[1]) throw new Error('MARKETING_VERSION is missing from project.yml');
  return match[1];
})();

export const repoUrl = 'https://github.com/OrtexIsArtem/vortex';
export const releasesUrl = `${repoUrl}/releases`;
export const contributingUrl = `${repoUrl}/blob/main/CONTRIBUTING.md`;
export const licenseUrl = `${repoUrl}/blob/main/LICENSE`;
export const issuesUrl = `${repoUrl}/issues`;
export const buildUrl = `${repoUrl}#build-it-yourself`;

/** Set once this version is published on GitHub Releases: the download button then fetches its zip directly. */
const released = false;

/** The zip the release workflow uploads for this version's tag, or the README's install steps until it exists. */
export const downloadUrl = released ? `${releasesUrl}/download/v${appVersion}/Vortex-v${appVersion}.zip` : `${repoUrl}#install`;
