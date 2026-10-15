import { getAllSubdomains } from '@/lib/subdomains';
import type { Metadata } from 'next';
import { headers } from 'next/headers';
import { AdminDashboard } from './dashboard';
import { rootDomain } from '@/lib/utils';
import { requestHost } from '@/lib/addresses';

// Upstream renders this page on demand without saying so: every Upstash
// command is a `cache: 'no-store'` fetch, which opts the route out of static
// rendering. A KV binding is not a fetch, so the choice is explicit here —
// the tenant list must never be baked in at build time.
export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: `Admin Dashboard | ${rootDomain}`,
  description: `Manage subdomains for ${rootDomain}`
};

export default async function AdminPage() {
  // TODO: You can add authentication here with your preferred auth provider
  const tenants = await getAllSubdomains();
  // The links to each tenant follow the host this page is served on
  // (lib/addresses.ts): subdomains on the root domain, /s/<tenant> elsewhere.
  const host = requestHost(await headers());

  return (
    <div className="min-h-screen bg-gray-50 p-4 md:p-8">
      <AdminDashboard tenants={tenants} host={host} />
    </div>
  );
}
