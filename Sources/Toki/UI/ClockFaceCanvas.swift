import SwiftUI

/// 時計盤の Canvas 描画。0:00 真上、時計回り、24 時間表示。
/// 描画順（spec 013 で背景帯 / 合成弧 / badge を追加、peek は改修で廃止）：
/// 1. 背景帯（24h timed event、最背面）
/// 2. リング輪郭
/// 3. 時刻マーク
/// 4. 合成弧（重なりグループの最大時間範囲、薄色背景、current 弧より長い event の存在を可視化）
/// 5. イベント円弧（past→future→current、各 group の current のみ、normal 色）
/// 6. badge `i/N`（重なり時の現 index / 総件数を表示、scroll 進行状況も伝わる）
/// 7. 中心ドット / 針（最前面）
struct ClockFaceCanvas: View {
    /// 現在時刻に対応する針の角度（ラジアン）。
    /// 角度変換は ViewModel 側で `calendar` を考慮して行うため、
    /// View は計算済みの値を受け取るだけにする。
    let nowAngle: Double
    /// 重なりグループ群（spec 013 で events から差し替え）。
    /// 各 group の current event を従来 events と同様に円弧描画する。
    let groups: [RenderableOverlapGroup]
    /// 24h timed event の背景帯（spec 013 で新規）。あれば全周に薄色塗り。
    let backgroundEvent: RenderableEvent?
    /// 針 / 中心ドット / 現在 event アウトラインのテーマカラー。
    /// 旧来の `.primary` から差し替え、ユーザー設定で変更可能（spec 008 拡張）。
    var themeColor: Color = .accentColor
    /// リングの太さ（event 円弧幅）。dim に対する比率（標準 0.08）。
    var ringThickness: CGFloat = 0.08
    /// 針の太さ（lineWidth、pt）。
    var handLineWidth: CGFloat = 1.5
    /// 文字サイズスケール（時刻マーク 0/6/12/18 用）。
    var textScale: CGFloat = 1.0
    /// 円自体（リング輪郭線）の lineWidth。
    var circleOutlineLineWidth: CGFloat = 0.75
    /// 円自体（リング輪郭線）の色。デフォルトは secondary 60%。
    var circleOutlineColor: Color = .secondary.opacity(0.6)
    /// 円弧クリック時に呼ばれる。位置は Canvas のローカル座標、geometry は描画時と同じ前提。
    var onTap: ((CGPoint, ClockGeometry) -> Void)? = nil
    /// マウスホバー時に呼ばれる。`.active(location)` / `.ended` の HoverPhase と
    /// 描画時と同じ ClockGeometry を渡す。
    var onHover: ((HoverPhase, ClockGeometry) -> Void)? = nil

    var body: some View {
        // GeometryReader で現在のレイアウトサイズを取り、描画とタップで同じ geometry を共有する。
        // 親 frame が変わってもヒットテストと描画がズレないようにする。
        GeometryReader { proxy in
            Canvas { ctx, size in
                let geometry = ClockGeometry.standard(in: size, ringThickness: ringThickness)
                // 1. 背景帯（最背面）
                drawBackgroundBand(in: &ctx, geometry: geometry, event: backgroundEvent)
                // 2. リング輪郭
                drawRingOutlines(in: &ctx, geometry: geometry)
                // 3. 時刻マーク
                drawHourMarks(in: &ctx, geometry: geometry)
                // 4. 合成弧（重なりグループの最大範囲、薄色背景）
                drawCompositeArcs(in: &ctx, geometry: geometry)
                // 5. event 円弧（各 group の current だけを従来通り描画、合成弧の上）
                drawEventArcs(in: &ctx, geometry: geometry)
                // 6. badge `i/N`
                drawBadges(in: &ctx, geometry: geometry)
                // 7. 中心ドット / 針（最前面）
                drawHand(in: &ctx, geometry: geometry, angle: nowAngle)
                drawCenterDot(in: &ctx, geometry: geometry)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        let geometry = ClockGeometry.standard(in: proxy.size, ringThickness: ringThickness)
                        onTap?(value.location, geometry)
                    }
            )
            .onContinuousHover(coordinateSpace: .local) { phase in
                let geometry = ClockGeometry.standard(in: proxy.size, ringThickness: ringThickness)
                onHover?(phase, geometry)
            }
        }
    }

    /// 内側リング輪郭線。時間トラックの内縁を示す。
    /// 外側はイベント円弧の外端で示唆されるため描画しない。
    private func drawRingOutlines(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let inner = Path(ellipseIn: CGRect(
            x: geometry.center.x - geometry.innerRadius,
            y: geometry.center.y - geometry.innerRadius,
            width: geometry.innerRadius * 2,
            height: geometry.innerRadius * 2
        ))
        ctx.stroke(inner, with: .color(circleOutlineColor), lineWidth: circleOutlineLineWidth)
    }

    /// 針の根元にある小さなドット。テーマカラーで強調する。
    private func drawCenterDot(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let dotRadius: CGFloat = 2.5
        let rect = CGRect(
            x: geometry.center.x - dotRadius,
            y: geometry.center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        ctx.fill(Path(ellipseIn: rect), with: .color(themeColor))
    }

    /// 0 / 6 / 12 / 18 の時刻マークをリングの内側に描く。
    /// 外周の外側に置くと 280pt の canvas 端でテキストが見切れるため内側配置にする。
    private func drawHourMarks(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let labels: [(hour: Int, text: String)] = [
            (0, "0"), (6, "6"), (12, "12"), (18, "18")
        ]
        let labelRadius = geometry.innerRadius * 0.86
        for label in labels {
            guard let tod = TimeOfDay(hour: label.hour, minute: 0) else { continue }
            let angle = tod.clockAngle
            let position = CGPoint(
                x: geometry.center.x + CGFloat(cos(angle)) * labelRadius,
                y: geometry.center.y + CGFloat(sin(angle)) * labelRadius
            )
            let text = Text(label.text)
                .font(.system(size: 9 * textScale))
                .foregroundStyle(.secondary)
            ctx.draw(text, at: position, anchor: .center)
        }
    }

    /// イベント円弧を描画する。current のアウトラインが最上位に来るよう描画順を制御する。
    /// spec 013 で events から groups に切替、各 group の current だけを描画する。
    private func drawEventArcs(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let currents = groups.map(\.current)
        let sorted = currents.sorted { Self.drawOrder($0.status) < Self.drawOrder($1.status) }
        for event in sorted {
            drawEventArc(in: &ctx, event: event, geometry: geometry)
        }
    }

    /// past → future → current の順で描画するための優先度。
    private static func drawOrder(_ status: EventStatus) -> Int {
        switch status {
        case .past: return 0
        case .future: return 1
        case .current: return 2
        }
    }

    /// 現在時刻を指す針を、中央テキストエリアの外側から外径まで描く。
    /// 中央 3 行テキスト（CurrentEventLabel）と針が視覚的に重ならないよう
    /// 内側にギャップを設けることで、針が文字を貫通して見える違和感を回避する。
    /// 角度計算は呼び出し側（ViewModel）で行い、View はラジアン値を受け取るだけ。
    private func drawHand(in ctx: inout GraphicsContext, geometry: ClockGeometry, angle: Double) {
        // 中央テキスト（3 行 × ~15pt）を避けるためのギャップ半径
        // spec 008: innerRadius に比例（28 / 85 ≈ 0.33）で動的サイズ対応
        let handInnerOffset: CGFloat = geometry.innerRadius * 0.33
        let startPoint = CGPoint(
            x: geometry.center.x + CGFloat(cos(angle)) * handInnerOffset,
            y: geometry.center.y + CGFloat(sin(angle)) * handInnerOffset
        )
        let endPoint = CGPoint(
            x: geometry.center.x + CGFloat(cos(angle)) * geometry.outerRadius,
            y: geometry.center.y + CGFloat(sin(angle)) * geometry.outerRadius
        )
        var path = Path()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        ctx.stroke(path, with: .color(themeColor), lineWidth: handLineWidth)
    }

    // MARK: - 新規描画 helper（spec 013）

    /// 背景帯を環状全周に薄色塗りで描画する（spec 013、24h timed event 用）。
    /// 色 = event.color × opacity 0.15（spec 013 §Open Questions §13）。
    /// `annulusPath` は内縁を半径 innerR の逆方向円弧で閉じるため、
    /// startAngle == endAngle だと閉じた図形にならない。
    /// 全周塗りは内外の同心円差分（Even-Odd 塗り）で実現する。
    private func drawBackgroundBand(in ctx: inout GraphicsContext,
                                    geometry: ClockGeometry,
                                    event: RenderableEvent?) {
        guard let ev = event else { return }
        var path = Path()
        path.addEllipse(in: CGRect(
            x: geometry.center.x - geometry.outerRadius,
            y: geometry.center.y - geometry.outerRadius,
            width: geometry.outerRadius * 2,
            height: geometry.outerRadius * 2
        ))
        path.addEllipse(in: CGRect(
            x: geometry.center.x - geometry.innerRadius,
            y: geometry.center.y - geometry.innerRadius,
            width: geometry.innerRadius * 2,
            height: geometry.innerRadius * 2
        ))
        ctx.fill(path, with: .color(Color(cgColor: ev.color).opacity(0.15)), style: FillStyle(eoFill: true))
    }

    /// 重なりグループの「合成弧」描画（spec 013 改修、peek 廃止後の代替）。
    /// 各グループの最早 start 〜 最遅 end の範囲を current 色 × opacity 0.25 で背景描画する。
    /// 「current 弧より裏に長い event がある」が一目で分かる。
    /// 単独 event（current 弧 == 合成弧）の場合も同じ範囲で薄色描画するため、
    /// 後段の drawEventArcs で描く normal 色弧が上に乗って実質見えない（描画コスト微増のみ）。
    private func drawCompositeArcs(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        for g in groups {
            // 単独 event は合成弧と current 弧が同じ範囲、描画する意味なし
            guard g.totalCount > 1 else { continue }
            let path = annulusPath(
                center: geometry.center,
                innerR: geometry.innerRadius,
                outerR: geometry.outerRadius,
                startAngle: g.groupStartAngle,
                endAngle: g.groupEndAngle
            )
            ctx.fill(path, with: .color(Color(cgColor: g.current.color).opacity(0.25)))
        }
    }

    /// badge `i/N` 描画（spec 013 改修）。totalCount > 1 のグループの弧の外側に Text 9pt。
    /// 外側オフセット 6pt、角度位置は current 弧の中央角度。
    /// 「3 件中の 2 件目」を直感的に伝える（scroll 進行状況も伝わる）。
    /// 角度規約は `drawHourMarks` と同じ：clockAngle はすでに描画座標系
    /// （0:00 が真上 = -π/2）なので、そのまま cos / sin で位置を取れる。
    private func drawBadges(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let badgeRadius = geometry.outerRadius + 6
        for g in groups where g.totalCount > 1 {
            let midAngle = (g.current.startAngle + g.current.endAngle) / 2
            let pos = CGPoint(
                x: geometry.center.x + CGFloat(cos(midAngle)) * badgeRadius,
                y: geometry.center.y + CGFloat(sin(midAngle)) * badgeRadius
            )
            let text = Text("\(g.currentIndex)/\(g.totalCount)")
                .font(.system(size: 9 * textScale))
                .foregroundStyle(.secondary)
            ctx.draw(text, at: pos, anchor: .center)
        }
    }
}
