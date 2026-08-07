//
//  DeveloperNoteView.swift
//  Titans
//

import SwiftUI

struct DeveloperNoteView: View {
    @Environment(\.appTheme) private var theme

    // ┌──────────────────────────────────────────────────────────────┐
    // │  👇 여기에 개발자의 말을 직접 작성하세요.                          │
    // │  문단을 나누려면 큰따옴표(") 안에서 그냥 줄바꿈을 하거나,          │
    // │  빈 줄을 넣으면 됩니다. 여러 문단도 그대로 유지됩니다.             │
    // └──────────────────────────────────────────────────────────────┘
    private let note = """
     안녕하세요 surFin 개발자입니다.
    
     먼저 surFin을 찾아주신 여러분께 진심으로 감사의 말씀을 드리며, 또 진심으로 환영합니다.
    
     여러분은 시가총액이 궁금할 때 어떻게 확인하시나요?
    
     저의 지난 4년을 돌아보자면, 시가총액 순위를 보여주는 적당한 사이트를 찾고 링크를 노션에 저장해 두었는데요.
    
     보고 싶을 때마다 노션에 들어가고, 링크를 저장해 둔 페이지를 찾고, 링크를 클릭하는 수고로움이 있었습니다.
    
     또 출처가 어디인지, 정확한 정보인지.. 
    
     조금씩 쌓여온 응어리진 마음으로 지금의 surFin을 만들게 되었습니다. 
    
     때문에 surFin은 늘 정보의 정확성, 경험의 직관성, 출처의 투명성을 지향합니다.
    
                    surFin = surfing + Finance
    
     시장의 등락 흐름이 마치 오르고 내리는 파도와 같고, 클릭 몇 번으로 내가 원하는 증권거래소로 가볍게 서핑(surfing)할 수 있는 환경을 제공한다는 의미입니다.
    
     surFin 아이콘은 우상향하는 주식 그래프와 큰 파도가 형성하는 배럴로 구성했고, 상승을 의미하는 초록 계열의 색을 입혀 디자인했습니다.
    
     KOSPI/KOSDAQ 데이터는 공공데이터포털 오픈 API를 활용해 EOD 형태로 영업일 기준 일 1회 가져오고 있습니다. 때문에 휴일 동안 금요일과 같은 데이터가 보여지는 것은 정상입니다. 
    
     그 외 데이터는 Twelve Data의 정식 라이선스를 발급받아 제공 중이며, 파싱 과정에서 경미한 오차가 있을 수 있습니다. 
    
     각 증권거래소의 공식데이터와 지속적으로 비교해 유지·보수 중이며, 이 부분을 늘 유념해 사용에 불편함이 없도록 더 좋은 서비스로 보답하겠습니다.
    
     지난 2~30년간 시대의 주도주를 놓치지 않고 따라갔다면 S&P 500 수익률을 압도하는 성과를 낼 수 있었습니다. 
    
     surFin의 모든 사용자들이, 시장이라는 거대한 파도 위에서 최고의 파도를 탈 수 있도록 돕는 서핑보드가 되겠습니다.
    
                         "Surfing the Finance"
    
                                     감사합니다.
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.label)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .background(theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("개발자 노트")
        .navigationBarTitleDisplayMode(.large)
    }
}
