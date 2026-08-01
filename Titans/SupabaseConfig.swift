//
//  SupabaseConfig.swift
//  Titans
//
//  Supabase 프로젝트 접속 상수. 여기 들어가는 두 값(URL·anon key)은 "공개돼도 안전한"
//  클라이언트 값이다. 실제 데이터 접근은 Postgres RLS(행 수준 보안) 정책이 통제하므로,
//  anon key가 앱 바이너리에 포함돼도 다른 유저의 데이터를 읽을 수 없다.
//
//  ⚠️ service_role 키는 절대 여기(=앱)에 넣지 않는다. 관리자 권한 키는 서버(Edge Function)
//     환경변수에만 존재한다. (계정 삭제 등 admin 작업 전용)
//

import Foundation

enum SupabaseConfig {
    /// Supabase 프로젝트 URL.
    static let url = URL(string: "https://eflfhjnndgcanikjpfym.supabase.co")!

    /// anon(public) 키 — RLS로 보호되는 공개 클라이언트 키.
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmbGZoam5uZGdjYW5pa2pwZnltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1NjExMTgsImV4cCI6MjEwMTEzNzExOH0.O6WM6ZvCbuVYB0LeIRNi-NIsiETGfqF43q76o1yI_YE"

    /// OAuth(Kakao 등) 웹 리다이렉트가 앱으로 돌아올 때 쓰는 커스텀 스킴 URL.
    /// Info.plist의 URL Types 및 Supabase Auth의 Redirect URLs에 동일하게 등록해야 한다.
    static let redirectURL = URL(string: "titans://auth-callback")!
}
