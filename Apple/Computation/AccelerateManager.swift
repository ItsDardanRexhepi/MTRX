// AccelerateManager.swift
// MTRX Apple Integration — Computation
//
// Accelerate framework for high-performance financial math

import Accelerate
import Foundation

// MARK: - AccelerateManager

final class AccelerateManager {

    static let shared = AccelerateManager()

    // MARK: - Portfolio Statistics

    func portfolioReturn(values: [Double]) -> Double {
        guard values.count >= 2, let first = values.first, let last = values.last, first != 0 else { return 0 }
        return (last - first) / first
    }

    func dailyReturns(prices: [Double]) -> [Double] {
        guard prices.count >= 2 else { return [] }
        var returns = [Double](repeating: 0, count: prices.count - 1)
        for i in 0..<returns.count {
            returns[i] = (prices[i + 1] - prices[i]) / prices[i]
        }
        return returns
    }

    func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        var result: Double = 0
        vDSP_meanvD(values, 1, &result, vDSP_Length(values.count))
        return result
    }

    func standardDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let avg = mean(values)
        var deviations = values.map { $0 - avg }
        var squaredDeviations = [Double](repeating: 0, count: values.count)
        vDSP_vsqD(&deviations, 1, &squaredDeviations, 1, vDSP_Length(values.count))
        let variance = mean(squaredDeviations)
        return sqrt(variance)
    }

    // MARK: - Risk Metrics

    func sharpeRatio(returns: [Double], riskFreeRate: Double = 0.02) -> Double {
        let avgReturn = mean(returns)
        let stdDev = standardDeviation(returns)
        guard stdDev > 0 else { return 0 }
        let annualizedReturn = avgReturn * 252
        let annualizedStdDev = stdDev * sqrt(252)
        return (annualizedReturn - riskFreeRate) / annualizedStdDev
    }

    func maxDrawdown(values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        var maxDD: Double = 0
        var peak = values[0]
        for value in values {
            if value > peak { peak = value }
            let dd = (peak - value) / peak
            if dd > maxDD { maxDD = dd }
        }
        return maxDD
    }

    func valueAtRisk(returns: [Double], confidence: Double = 0.95) -> Double {
        let sorted = returns.sorted()
        let index = Int((1 - confidence) * Double(sorted.count))
        guard index < sorted.count else { return 0 }
        return abs(sorted[index])
    }

    // MARK: - Correlation

    func correlation(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, !x.isEmpty else { return 0 }
        let n = Double(x.count)
        let meanX = mean(x)
        let meanY = mean(y)

        var covariance: Double = 0
        var varX: Double = 0
        var varY: Double = 0

        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            covariance += dx * dy
            varX += dx * dx
            varY += dy * dy
        }

        guard varX > 0, varY > 0 else { return 0 }
        return covariance / (sqrt(varX) * sqrt(varY))
    }

    // MARK: - Matrix Operations (Portfolio Optimization)

    func matrixMultiply(a: [Double], b: [Double], rowsA: Int, colsA: Int, colsB: Int) -> [Double] {
        var result = [Double](repeating: 0, count: rowsA * colsB)
        vDSP_mmulD(a, 1, b, 1, &result, 1, vDSP_Length(rowsA), vDSP_Length(colsB), vDSP_Length(colsA))
        return result
    }

    // MARK: - Moving Averages

    func simpleMovingAverage(values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }
        var result: [Double] = []
        for i in (period - 1)..<values.count {
            let window = Array(values[(i - period + 1)...i])
            result.append(mean(window))
        }
        return result
    }

    func exponentialMovingAverage(values: [Double], period: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let multiplier = 2.0 / Double(period + 1)
        var ema = [values[0]]
        for i in 1..<values.count {
            let newEma = (values[i] - ema[i - 1]) * multiplier + ema[i - 1]
            ema.append(newEma)
        }
        return ema
    }

    // MARK: - Compound Interest

    func compoundInterest(principal: Double, rate: Double, periods: Int, compoundingPerYear: Int = 12) -> Double {
        let r = rate / Double(compoundingPerYear)
        let n = Double(periods * compoundingPerYear)
        return principal * pow(1 + r, n)
    }

    func presentValue(futureValue: Double, rate: Double, periods: Int) -> Double {
        return futureValue / pow(1 + rate, Double(periods))
    }
}
