import QtQuick
import QtQuick.Controls as QQC2

QQC2.TextField {
    placeholderText: "2560x1440"
    validator: RegularExpressionValidator {
        regularExpression: /\d{3,5}x\d{3,5}/
    }
}
