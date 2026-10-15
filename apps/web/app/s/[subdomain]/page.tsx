import Link from 'next/link';
import type { Metadata } from 'next';
import { headers } from 'next/headers';
import { notFound } from 'next/navigation';
import { getSubdomainData } from '@/lib/subdomains';
import {
  homeUrl,
  requestHost,
  siteAddress,
  tenantAddress
} from '@/lib/addresses';

export async function generateMetadata({
  params
}: {
  params: Promise<{ subdomain: string }>;
}): Promise<Metadata> {
  const { subdomain } = await params;
  const subdomainData = await getSubdomainData(subdomain);
  const host = requestHost(await headers());

  if (!subdomainData) {
    return {
      title: siteAddress(host)
    };
  }

  // `<tenant>.<root>` when served on the root domain, `<host>/s/<tenant>`
  // anywhere else (lib/addresses.ts).
  const address = tenantAddress(subdomain, host);
  return {
    title: address,
    description: `Subdomain page for ${address}`
  };
}

export default async function SubdomainPage({
  params
}: {
  params: Promise<{ subdomain: string }>;
}) {
  const { subdomain } = await params;
  const subdomainData = await getSubdomainData(subdomain);

  if (!subdomainData) {
    notFound();
  }

  const host = requestHost(await headers());

  return (
    <div className="flex min-h-screen flex-col bg-gradient-to-b from-blue-50 to-white p-4">
      <div className="absolute top-4 right-4">
        <Link
          href={homeUrl(host)}
          className="text-sm text-gray-500 hover:text-gray-700 transition-colors"
        >
          {siteAddress(host)}
        </Link>
      </div>

      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <div className="text-9xl mb-6">{subdomainData.emoji}</div>
          <h1 className="text-4xl font-bold tracking-tight text-gray-900">
            Welcome to {tenantAddress(subdomain, host)}
          </h1>
          <p className="mt-3 text-lg text-gray-600">
            This is your custom subdomain page
          </p>
        </div>
      </div>
    </div>
  );
}
