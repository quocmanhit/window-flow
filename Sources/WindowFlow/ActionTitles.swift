import WindowFlowCore

extension WindowAction {
    var title: String {
        switch self {
        case .leftHalf: tr("Left half", "Nửa trái")
        case .rightHalf: tr("Right half", "Nửa phải")
        case .topHalf: tr("Top half", "Nửa trên")
        case .bottomHalf: tr("Bottom half", "Nửa dưới")
        case .topLeft: tr("Top left", "Góc trên trái")
        case .topRight: tr("Top right", "Góc trên phải")
        case .bottomLeft: tr("Bottom left", "Góc dưới trái")
        case .bottomRight: tr("Bottom right", "Góc dưới phải")
        case .firstThird: tr("First third", "Một phần ba đầu")
        case .centerThird: tr("Center third", "Một phần ba giữa")
        case .lastThird: tr("Last third", "Một phần ba cuối")
        case .firstTwoThirds: tr("First two-thirds", "Hai phần ba đầu")
        case .lastTwoThirds: tr("Last two-thirds", "Hai phần ba cuối")
        case .maximize: tr("Maximize", "Phóng to")
        case .almostMaximize: tr("Almost maximize", "Gần toàn màn hình")
        case .maximizeHeight: tr("Maximize height", "Cao tối đa")
        case .larger: tr("Larger", "To ra")
        case .smaller: tr("Smaller", "Nhỏ lại")
        case .center: tr("Center", "Căn giữa")
        case .restore: tr("Restore", "Khôi phục")
        case .nextDisplay: tr("Next display", "Màn hình tiếp theo")
        case .previousDisplay: tr("Previous display", "Màn hình trước")
        }
    }
}
