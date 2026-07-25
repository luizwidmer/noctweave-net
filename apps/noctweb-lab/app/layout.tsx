import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const title = "Noctweb Lab — Noctweave development workspace";
const description =
  "Build, publish, resolve, inspect, and fault-test Noctweb sites in a deterministic local workspace.";

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#0a0f0d",
};

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const suppliedHost =
    requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const host =
    suppliedHost && /^[a-z0-9.-]+(?::\d+)?$/i.test(suppliedHost)
      ? suppliedHost
      : "localhost:5173";
  const protocol =
    requestHeaders.get("x-forwarded-proto") ??
    (host.startsWith("localhost") || host.startsWith("127.0.0.1")
      ? "http"
      : "https");
  const origin = `${protocol === "http" ? "http" : "https"}://${host}`;
  const socialImage = `${origin}/og.png`;

  return {
    title,
    description,
    openGraph: {
      title,
      description,
      type: "website",
      images: [{ url: socialImage, width: 1734, height: 907 }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [socialImage],
    },
    applicationName: "Noctweb Lab",
    appleWebApp: {
      capable: true,
      title: "Noctweb Lab",
      statusBarStyle: "black-translucent",
    },
    icons: {
      icon: [{ url: `${origin}/app-icon.png`, type: "image/png" }],
      apple: [{ url: `${origin}/app-icon.png`, type: "image/png" }],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
