import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Titans — 글로벌 시가총액 순위',
  description: '실시간 글로벌 빅테크 시가총액 순위',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  )
}
