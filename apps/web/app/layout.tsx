import type { Metadata } from 'next';
import { Geist } from 'next/font/google';
import { CloudflareWebAnalytics } from '@/components/analytics';
import { SITE_NAME } from './site';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin']
});

export const metadata: Metadata = {
  title: SITE_NAME,
  description: 'Next.js template for building a multi-tenant SaaS.'
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${geistSans.variable} antialiased`}>
        {children}
        <CloudflareWebAnalytics />
      </body>
    </html>
  );
}
