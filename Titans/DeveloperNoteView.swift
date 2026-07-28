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
     안녕하세요 Titans 개발자 이승훈입니다.
    
     먼저 Titans 앱을 찾아주신 여러분을 진심으로 환영하고 또 감사의 말씀드립니다.
    
     저는 토스어플로 주식한 지 4년차입니다. 주식을 하다보니 LVMH 등 기업들을도 보고싶었습니다. 
    
     근데 마땅히 토스처럼 깔끔한 디자인이면서 증권거래소별로 기업목록을 제공하는 앱이 없더라구요. 그래서 만들게 되었습니다. 토스처럼 깔끔한 UI에 글로벌 거래증권소 기업 시가총액 목록 제공! 제가 주식하면서 필요하다고 느낀 기능들 위주로 구현했습니다. 내가 원하는 기업의 배당락일을 캘린더에 직관적으로 보고싶어서 이 기능도 함께 추가했습니다. 구독제로 이용되니 많관많부!
    
     지금 코스피/코스닥 데이터는 전적으로 공공데이터포털 오픈 API에서 가져오고 있습니다. 
    
     그렇다보니 종가기준 다음날 업데이트되고 있는데 점차 사용자가 늘고 수익이 나기 시작하면 수익을 유료데이터플랫폼에서 가져와 여러분께 실시간 데이터로 제공드리고자하는 다음스텝의 목표가 있습니다. 그러니 많이 광고 많이 봐주시고 자주 사용해주세요. 
    
     저는 여러분의 목소리에 귀기울이면서 부족한 부분은 어떤 것이고 필요로하는 기능은 무엇인지 끊임없이 고민하는 개발자가 되도록하겠습니다. 
    
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
