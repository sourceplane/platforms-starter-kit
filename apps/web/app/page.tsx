import Link from 'next/link';
import { headers } from 'next/headers';
import { SubdomainForm } from './subdomain-form';
import { SITE_NAME } from './site';
import { rootDomain } from '@/lib/utils';
import { onRootDomain, requestHost, siteAddress } from '@/lib/addresses';

// Rendered per request: what the page offers depends on the host it is asked
// on (lib/addresses.ts) — subdomains of the root domain there, a path on this
// host anywhere else (workers.dev before a custom domain is attached).
export default async function HomePage() {
  const host = requestHost(await headers());
  const pathBase = onRootDomain(host) ? null : `${host ?? ''}/s/`;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gradient-to-b from-blue-50 to-white p-4 relative">
      <div className="absolute top-4 right-4">
        <Link
          href="/admin"
          className="text-sm text-gray-500 hover:text-gray-700 transition-colors"
        >
          Admin
        </Link>
      </div>

      <div className="w-full max-w-md space-y-8">
        <div className="text-center">
          <p className="text-sm font-medium text-blue-600">{SITE_NAME}</p>
          <h1 className="mt-2 text-4xl font-bold tracking-tight text-gray-900 break-words">
            {siteAddress(host)}
          </h1>
          <p className="mt-3 text-lg text-gray-600">
            Create your own subdomain with a custom emoji
          </p>
        </div>

        <div className="mt-8 bg-white shadow-md rounded-lg p-6">
          <SubdomainForm pathBase={pathBase} />
        </div>

        {pathBase && (
          <p className="text-center text-xs text-gray-500">
            {`Tenants open on this host under /s/ until ${rootDomain}'s wildcard route points at this site; then each one is <name>.${rootDomain}.`}
          </p>
        )}
      </div>
    </div>
  );
}
