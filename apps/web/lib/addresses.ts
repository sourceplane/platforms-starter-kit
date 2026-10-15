// Where a tenant lives, as seen from the host a request came in on.
//
// Upstream gives every tenant a subdomain of the root domain,
// `<tenant>.<NEXT_PUBLIC_ROOT_DOMAIN>`, and proxy.ts rewrites that host's `/`
// to `/s/<tenant>`. A subdomain needs a wildcard route on a zone you own, and
// a fresh deployment has none: it answers on workers.dev (and `wrangler dev`
// on 127.0.0.1), where `<tenant>.<worker>.<account>.workers.dev` does not
// resolve. So on any host OFF the root domain a tenant is reached by PATH on
// that same host — `/s/<tenant>`, the page the proxy's rewrite lands on
// anyway. Creating a tenant and visiting it works from the first deploy, and
// the links turn into subdomains by themselves once the root domain's
// wildcard route points at the Worker: requests then arrive ON the root
// domain.
import { protocol, rootDomain } from '@/lib/utils';

type Host = string | null | undefined;

/** The host a request was made to, as the server sees it. */
export function requestHost(headers: {
  get(name: string): string | null;
}): string | null {
  const host = headers.get('x-forwarded-host') ?? headers.get('host');
  return host ? host.split(',')[0].trim() || null : null;
}

/** Whether `host` is the root domain or one of its subdomains — where tenants are subdomains. */
export function onRootDomain(host: Host): boolean {
  if (!host) return false;
  const root = rootDomain.toLowerCase();
  // A root domain with a port (`localhost:3000`, the local default) matches
  // with its port; a public one matches by name, whatever port the Host
  // header carries.
  const name = root.includes(':')
    ? host.toLowerCase()
    : host.toLowerCase().split(':')[0];
  return name === root || name.endsWith(`.${root}`);
}

/** The URL a tenant is visited at, from a page served on `host`. */
export function tenantUrl(subdomain: string, host: Host): string {
  return onRootDomain(host)
    ? `${protocol}://${subdomain}.${rootDomain}`
    : `/s/${subdomain}`;
}

/** A tenant's address as people read it on a page served on `host`. */
export function tenantAddress(subdomain: string, host: Host): string {
  return onRootDomain(host) || !host
    ? `${subdomain}.${rootDomain}`
    : `${host}/s/${subdomain}`;
}

/** The landing page, from a page served on `host`. */
export function homeUrl(host: Host): string {
  return onRootDomain(host) ? `${protocol}://${rootDomain}` : '/';
}

/** The name the site goes by on `host`: the root domain on it, the host itself anywhere else. */
export function siteAddress(host: Host): string {
  return onRootDomain(host) || !host ? rootDomain : host;
}
