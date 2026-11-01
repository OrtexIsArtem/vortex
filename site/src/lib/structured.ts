// What search engines read about a page (schema.org JSON-LD): the landing's graph, and a guide's. Pure: the head
// (layouts/Base.astro) serializes it, and the tests read it.
import { inlineText } from './inline';

/** Other apps are called Vortex too: the names people may look this one up by. */
const alternateName = ['Vortex for Mac', 'Vortex notch app'];

const author = { '@type': 'Person', name: 'Artem Pronenko', url: 'https://github.com/OrtexIsArtem' };

/** The site, the same on every page. `home` is the English landing's address, which the site's ids hang on. */
function website(home: string, tags: readonly string[]) {
  return { '@type': 'WebSite', '@id': `${home}#website`, name: 'Vortex', alternateName, url: home, inLanguage: tags };
}

export interface LandingGraph {
  home: string;
  /** The landing in this page's language. */
  page: string;
  title: string;
  description: string;
  /** This page's language, and every language's (the site's). */
  tag: string;
  tags: readonly string[];
  image: string;
  appVersion: string;
  downloadUrl: string;
  licenseUrl: string;
  repoUrl: string;
}

/** The landing: the site, this page, the app and its source. The app is one thing in every language, so it keeps the
 * English page as its address. The FAQ adds its own (components/Faq.astro). */
export function landingGraph(o: LandingGraph): object[] {
  return [
    website(o.home, o.tags),
    {
      '@type': 'WebPage',
      '@id': `${o.page}#webpage`,
      url: o.page,
      name: o.title,
      description: o.description,
      inLanguage: o.tag,
      isPartOf: { '@id': `${o.home}#website` },
      about: { '@id': `${o.home}#app` },
    },
    {
      '@type': 'SoftwareApplication',
      '@id': `${o.home}#app`,
      name: 'Vortex',
      alternateName,
      description: o.description,
      url: o.home,
      image: o.image,
      applicationCategory: 'UtilitiesApplication',
      operatingSystem: 'macOS 14 or later',
      processorRequirements: 'Apple silicon',
      softwareVersion: o.appVersion,
      downloadUrl: o.downloadUrl,
      license: o.licenseUrl,
      isAccessibleForFree: true,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      author,
      sameAs: [o.repoUrl],
    },
    {
      '@type': 'SoftwareSourceCode',
      '@id': `${o.home}#source`,
      name: 'Vortex',
      codeRepository: o.repoUrl,
      programmingLanguage: 'Swift',
      runtimePlatform: 'macOS',
      license: o.licenseUrl,
      targetProduct: { '@id': `${o.home}#app` },
    },
  ];
}

export interface ArticleGraph {
  home: string;
  /** The landing in this page's language: the breadcrumb's first step. */
  landing: string;
  page: string;
  title: string;
  heading: string;
  description: string;
  /** The page's short name: the breadcrumb's last step. */
  label: string;
  tag: string;
  tags: readonly string[];
  image: string;
  published: Date;
  modified: Date;
  /** The questions the page shows; answers with the site's inline marks (lib/inline.ts). */
  faq: readonly { q: string; a: string }[];
}

/** A day, as schema.org reads it: 2026-11-01. */
const day = (date: Date) => date.toISOString().slice(0, 10);

/** A guide: the site, the page, the article about the app, the way back to the landing and, when the page shows
 * questions, those questions. */
export function articleGraph(o: ArticleGraph): object[] {
  const graph: object[] = [
    website(o.home, o.tags),
    {
      '@type': 'WebPage',
      '@id': `${o.page}#webpage`,
      url: o.page,
      name: o.title,
      description: o.description,
      inLanguage: o.tag,
      isPartOf: { '@id': `${o.home}#website` },
      breadcrumb: { '@id': `${o.page}#breadcrumb` },
      mainEntity: { '@id': `${o.page}#article` },
    },
    {
      '@type': 'TechArticle',
      '@id': `${o.page}#article`,
      headline: o.heading,
      description: o.description,
      inLanguage: o.tag,
      url: o.page,
      image: o.image,
      datePublished: day(o.published),
      dateModified: day(o.modified),
      author,
      mainEntityOfPage: { '@id': `${o.page}#webpage` },
      isPartOf: { '@id': `${o.home}#website` },
      about: { '@id': `${o.home}#app` },
    },
    {
      '@type': 'BreadcrumbList',
      '@id': `${o.page}#breadcrumb`,
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'Vortex', item: o.landing },
        { '@type': 'ListItem', position: 2, name: o.label, item: o.page },
      ],
    },
  ];
  if (o.faq.length > 0) {
    graph.push({
      '@type': 'FAQPage',
      '@id': `${o.page}#faq`,
      inLanguage: o.tag,
      isPartOf: { '@id': `${o.page}#webpage` },
      mainEntity: o.faq.map((item) => ({
        '@type': 'Question',
        name: item.q,
        acceptedAnswer: { '@type': 'Answer', text: inlineText(item.a) },
      })),
    });
  }
  return graph;
}

/** The graph as a <script type="application/ld+json">'s text: a `<` inside can't end the script. */
export function serializeGraph(graph: readonly object[]): string {
  return JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replace(/</g, '\\u003c');
}
