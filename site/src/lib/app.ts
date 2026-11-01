import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/** The version in the Xcode project: what a local build shows, with no release to ask about. */
const projectVersion: string = (() => {
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

/**
 * The newest published release, as CI reads it from GitHub before each build (site.yml), which runs again whenever a
 * release is published: its version and its zip. A version raised in project.yml for the next release never shows
 * before that release is out, and no link needs updating by hand.
 */
const release = (() => {
  const version = process.env.RELEASE_VERSION?.replace(/^v/, '');
  const zip = process.env.RELEASE_ZIP;
  return version && zip?.startsWith(`${releasesUrl}/download/`) ? { version, zip } : null;
})();

/** The version the page offers: the newest release's, or the project's in a local build. */
export const appVersion: string = release?.version ?? projectVersion;

/** The release's zip, downloaded straight away; the README's install steps when no release is known. */
export const downloadUrl = release?.zip ?? `${repoUrl}#install`;
