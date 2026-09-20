from PIL import Image

img = Image.open('assets/icon/app_icon.jpg').convert('RGBA')
datas = img.getdata()

newData = []
for item in datas:
    # Change dark pixels to transparent
    if item[0] < 40 and item[1] < 40 and item[2] < 40:
        newData.append((0, 0, 0, 0))
    else:
        newData.append(item)

img.putdata(newData)
img.save('assets/icon/app_icon.png', "PNG")
