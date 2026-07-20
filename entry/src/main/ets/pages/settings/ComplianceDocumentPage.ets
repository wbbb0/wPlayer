import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import {
  PageScrollBehavior,
  PageScrollContentBehavior
} from '../../components/layout/PageScrollBehavior';

export class ComplianceSection {
  readonly title: string;
  readonly paragraphs: Array<string>;

  constructor(title: string, paragraphs: Array<string>) {
    this.title = title;
    this.paragraphs = paragraphs;
  }
}

@Component
export struct ComplianceDocumentPage {
  @Prop sections: Array<ComplianceSection> = [];
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  @Builder
  private Section(section: ComplianceSection) {
    Column({ space: 10 }) {
      Text(section.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      ForEach(section.paragraphs, (paragraph: string, index: number) => {
        Text(paragraph)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(21)
          .width('100%')
      }, (_paragraph: string, index: number) => index.toString())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        ForEach(this.sections, (section: ComplianceSection, index: number) => {
          this.Section(section)
        }, (_section: ComplianceSection, index: number) => index.toString())
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: PageLayoutSpec.secondaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(this.contentBehavior)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .attributeModifier(this.scrollBehavior)
  }
}
