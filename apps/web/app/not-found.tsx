'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { rootDomain, protocol } from '@/lib/utils';
import { homeUrl, onRootDomain, siteAddress } from '@/lib/addresses';

export default function NotFound() {
  const [subdomain, setSubdomain] = useState<string | null>(null);
  // Upstream links the root domain. Off it (workers.dev, before a custom
  // domain) the landing page is this host's `/` (lib/addresses.ts); the
  // server render cannot know the host, so it is settled once mounted.
  const [home, setHome] = useState({
    href: `${protocol}://${rootDomain}`,
    label: rootDomain,
    onRoot: true
  });
  const pathname = usePathname();

  useEffect(() => {
    const host = window.location.host;
    setHome({
      href: homeUrl(host),
      label: siteAddress(host),
      onRoot: onRootDomain(host)
    });
    // Extract subdomain from URL if we're on a tenant's path page
    if (pathname?.startsWith('/s/')) {
      const extractedSubdomain = pathname.split('/')[2];
      if (extractedSubdomain) {
        setSubdomain(extractedSubdomain);
      }
    } else {
      // Try to extract from hostname for direct subdomain access
      const hostname = window.location.hostname;
      if (hostname.includes(`.${rootDomain.split(':')[0]}`)) {
        const extractedSubdomain = hostname.split('.')[0];
        setSubdomain(extractedSubdomain);
      }
    }
  }, [pathname]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gradient-to-b from-blue-50 to-white p-4">
      <div className="text-center">
        <h1 className="text-4xl font-bold tracking-tight text-gray-900">
          {subdomain ? (
            home.onRoot ? (
              <>
                <span className="text-blue-600">{subdomain}</span>.{rootDomain}{' '}
                doesn't exist
              </>
            ) : (
              <>
                {home.label}/s/<span className="text-blue-600">{subdomain}</span>{' '}
                doesn't exist
              </>
            )
          ) : (
            'Subdomain Not Found'
          )}
        </h1>
        <p className="mt-3 text-lg text-gray-600">
          This subdomain hasn't been created yet.
        </p>
        <div className="mt-6">
          <Link
            href={home.href}
            className="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
          >
            {subdomain ? `Create ${subdomain}` : `Go to ${home.label}`}
          </Link>
        </div>
      </div>
    </div>
  );
}
