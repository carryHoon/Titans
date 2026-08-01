import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Titans — 개인정보처리방침',
  description: 'Titans 앱 개인정보처리방침',
}

// 시행일 — 방침 내용이 바뀌면 이 날짜도 함께 갱신한다.
const EFFECTIVE_DATE = '2026년 8월 2일'

// ⚠️ 배포 전 반드시 실제 문의 이메일로 교체할 것. (placeholder 상태로 배포 금지)
const CONTACT_EMAIL = '«문의 이메일 주소»'

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-8">
      <h2 className="text-lg font-bold text-gray-900">{title}</h2>
      <div className="mt-2 space-y-2 text-[15px] leading-7 text-gray-700">{children}</div>
    </section>
  )
}

export default function PrivacyPolicyPage() {
  return (
    <main className="mx-auto max-w-2xl px-5 py-12">
      <h1 className="text-2xl font-bold text-gray-900">개인정보처리방침</h1>
      <p className="mt-2 text-sm text-gray-500">시행일: {EFFECTIVE_DATE}</p>

      <p className="mt-6 text-[15px] leading-7 text-gray-700">
        Titans(이하 &lsquo;서비스&rsquo;)는 이용자의 개인정보를 중요하게 생각하며, 관련 법령을
        준수하기 위해 노력합니다. 본 방침은 서비스가 어떤 개인정보를 수집·이용하며, 이를 위해
        어떤 조치를 취하는지 안내합니다.
      </p>

      <Section title="1. 수집하는 개인정보 항목">
        <p>서비스는 계정 생성 및 이용 과정에서 아래 정보를 수집합니다.</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>
            <strong>계정 식별자</strong>: 계정마다 자동으로 생성되는 고유 식별자(UUID) 및 로그인
            수단(Apple, 카카오)이 제공하는 고유 식별자
          </li>
          <li>
            <strong>이메일 주소</strong>(선택): 이메일로 직접 가입하거나, 소셜 로그인에서
            이메일 제공에 동의한 경우에 한해 수집됩니다. 소셜 로그인에서 이메일 제공에 동의하지
            않아도 서비스를 이용할 수 있습니다.
          </li>
          <li>
            <strong>이름</strong>(선택): Apple로 로그인할 때 이용자가 제공에 동의한 경우에 한해
            수집됩니다.
          </li>
          <li>
            <strong>서비스 이용 설정</strong>: 화면 모드(라이트/다크), 알림 사용 여부 등 기기 간
            동기화를 위한 앱 설정값
          </li>
        </ul>
        <p>
          서비스는 위치정보, 연락처, 결제·금융계좌 정보, 광고 식별자를 수집하지 않으며, 이용자의
          행동을 추적하거나 광고 목적의 프로파일링을 하지 않습니다.
        </p>
      </Section>

      <Section title="2. 개인정보의 수집 방법">
        <p>
          이용자가 회원가입 및 로그인(Apple, 카카오, 이메일)을 진행하거나, 앱 내 설정을 변경할 때
          해당 정보가 수집됩니다.
        </p>
      </Section>

      <Section title="3. 개인정보의 이용 목적">
        <ul className="list-disc space-y-1 pl-5">
          <li>회원 식별 및 계정 인증</li>
          <li>이용자의 여러 기기 간 앱 설정 동기화</li>
        </ul>
        <p>서비스는 수집한 개인정보를 위 목적 외의 용도로 이용하지 않습니다.</p>
      </Section>

      <Section title="4. 개인정보의 보유 및 파기">
        <p>
          서비스는 이용자가 계정을 유지하는 동안 개인정보를 보유하며, 회원 탈퇴 시 지체 없이
          파기합니다. 이용자는 앱 내 <strong>&lsquo;회원 탈퇴&rsquo;</strong> 기능을 통해 언제든지
          계정과 동기화된 모든 데이터의 영구 삭제를 직접 요청할 수 있으며, 요청 즉시 복구할 수 없도록
          삭제됩니다.
        </p>
      </Section>

      <Section title="5. 개인정보 처리의 위탁">
        <p>
          서비스는 원활한 운영을 위해 아래와 같이 개인정보 처리를 위탁하고 있습니다. 각 수탁사는
          위탁받은 업무 범위 내에서만 개인정보를 처리합니다.
        </p>
        <ul className="list-disc space-y-1 pl-5">
          <li>
            <strong>Supabase, Inc.</strong> — 계정 인증 및 데이터베이스 호스팅
          </li>
          <li>
            <strong>Apple Inc.</strong> — Sign in with Apple 로그인 처리
          </li>
          <li>
            <strong>Kakao Corp.</strong> — 카카오 로그인 처리
          </li>
        </ul>
        <p>
          위 수탁사의 서버는 국외에 위치할 수 있습니다. 이용자가 소셜 로그인 또는 계정 인증을
          진행하는 경우, 계정 식별자 및 (동의한 경우) 이메일·이름이 해당 사업자의 국외 서버에
          저장·처리될 수 있습니다.
        </p>
      </Section>

      <Section title="6. 개인정보의 제3자 제공">
        <p>
          서비스는 이용자의 개인정보를 제3자에게 판매하거나 제공하지 않습니다. 다만 법령에 따라
          요구되는 경우에는 관련 법령이 정한 절차와 방법에 따를 수 있습니다.
        </p>
      </Section>

      <Section title="7. 이용자의 권리">
        <p>
          이용자는 언제든지 자신의 개인정보에 대한 열람·정정·삭제·처리정지를 요구할 수 있습니다.
          계정 및 동기화 데이터의 삭제는 앱 내 &lsquo;회원 탈퇴&rsquo; 기능으로 직접 수행할 수
          있으며, 그 밖의 요청은 아래 문의처로 연락하시면 지체 없이 조치합니다.
        </p>
      </Section>

      <Section title="8. 만 14세 미만 아동의 개인정보">
        <p>
          서비스는 만 14세 미만 아동의 개인정보를 의도적으로 수집하지 않습니다. 만 14세 미만
          아동의 개인정보가 수집된 사실이 확인되면 지체 없이 삭제합니다.
        </p>
      </Section>

      <Section title="9. 개인정보 보호 문의">
        <p>
          개인정보 처리에 관한 문의, 불만, 권리 행사 요청은 아래로 연락해 주시기 바랍니다.
        </p>
        <p>
          이메일:{' '}
          <a href={`mailto:${CONTACT_EMAIL}`} className="text-blue-600 underline">
            {CONTACT_EMAIL}
          </a>
        </p>
      </Section>

      <Section title="10. 방침의 변경">
        <p>
          본 개인정보처리방침의 내용이 변경되는 경우, 변경 사항을 본 페이지를 통해 공지합니다.
        </p>
      </Section>
    </main>
  )
}
