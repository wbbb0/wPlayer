@Builder
function MenuSectionDividerContent() {
  Row() {
    Divider()
      .strokeWidth(1)
      .color($r('app.color.text_tertiary'))
      .opacity(0.25)
  }
  .width('100%')
  .height(9)
  .padding({ left: 16, right: 16 })
}

@Builder
export function MenuSectionDivider() {
  MenuItem(MenuSectionDividerContent)
    .enabled(false)
    .height(9)
}
