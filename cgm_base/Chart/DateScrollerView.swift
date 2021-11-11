//
//  DateScrollerView.swift
//  cgm_base
//
//  Created by Rajneesh on 11/11/21.
//

import SwiftUI

struct DateScrollerView: View {
    var viewModel : DateScrollerViewModel = DateScrollerViewModel()
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { value in
                HStack(spacing: 20) {
                    ForEach(viewModel.dates, id: \.id) { model in
                        VStack() {
                            Text(model.dateString)
                                .foregroundColor(.black)
                                .font(.caption)
                                .fontWeight(.light)
                                .id(model.index)
                            Spacer()
                                .frame(height: 5)
                            Button(action: {
                                print("Button Action")
                            }) {
                                Text(model.dayString)
                                    .font(.caption)
                                    .fontWeight(.light)
                                    .frame(width: 25, height: 25)
                                    .foregroundColor(Color.black)
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.red, lineWidth: 1)
                                            .opacity(1.0)
                                    )
                            }
                        }
                    }
                }.padding(1)
                .onAppear {
                    value.scrollTo(viewModel.dates.last!.index)
                }
            }
        }
    }
}

struct DateScrollerViewModel {
    
    var dates : [DateScrollerModel] {
        var dateArray: [DateScrollerModel] = []
        let numberOfDays = 15
        for i in (0..<numberOfDays).reversed() {
            let date = Date()
            let dateModel = DateScrollerModel(date: date.adding(minutes: i * -24 * 60), index: i)
            dateArray.append(dateModel)
        }
        return dateArray
    }
}

struct DateScrollerModel {
    let id = UUID()
    var index : Int
    var date : Date
    init(date:Date, index:Int) {
        self.date = date
        self.index = index
    }
    var dateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd"
        return dateFormatter.string(from: date)
    }
    var dayString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E"
        return String(dateFormatter.string(from: date).first ?? " ")
    }
}


struct DateScrollerView_Previews: PreviewProvider {
    static var previews: some View {
        DateScrollerView()
    }
}
