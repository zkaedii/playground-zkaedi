import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "The Orb - UUPSTokenV2 Visualization",
  description: "A hypnotic 3D visualization of token supply on Arbitrum One",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">
        {children}
      </body>
    </html>
  );
}
