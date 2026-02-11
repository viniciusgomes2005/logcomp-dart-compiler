
void calculator(String text){
    String filtered_text = "";
    List<String> operators = ["+","-"];
    for(int i = 0; i < text.length; i++){
        if(operators.contains(text[i])){
            filtered_text += " ${text[i] }";
        } else {
            filtered_text += text[i];
        }
    }
    List<String> wrong_phrease = filtered_text.split(" ");
    List<String> phrease = [];
    for (String item in wrong_phrease){
        if (item.isNotEmpty){
            phrease.add(item);
        }
    }
    int value = 0;
    String operator = "+";
    bool isOperator = true;
    print(phrease);
    for (String item in phrease){
        if(isOperator == operators.contains(item)){
            print("$item, ${isOperator.toString()}");
            throw Exception();
        }

        if(phrease.last == item && operators.contains(item)){
            throw Exception();
        }
        isOperator = operators.contains(item);
        if (isOperator){

            operator = item;
        } 
        else{
            switch(operator){ 
                case "+":
                    value+=int.parse(item);
                    break;
                case "-":
                    value-=int.parse(item);
            }
        }
    }
    print(value);
}

void main(List<String> args) {
  if (args.isEmpty) {
    print("Use: dart run main.dart 10 + 5 - 3");
    return;
  }
  calculator(args.join(" "));
}